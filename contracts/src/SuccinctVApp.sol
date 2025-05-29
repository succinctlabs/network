// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    Receipt,
    Actions,
    ActionsInternal,
    DepositInternal,
    WithdrawInternal,
    AddSignerInternal,
    RemoveSignerInternal
} from "./libraries/Actions.sol";
import {FeeCalculator} from "./libraries/FeeCalculator.sol";
import {
    PublicValuesStruct,
    ReceiptStatus,
    Action,
    ActionType,
    DepositAction,
    WithdrawAction,
    AddSignerAction,
    RemoveSignerAction
} from "./libraries/PublicValues.sol";
import {ISuccinctVApp} from "./interfaces/ISuccinctVApp.sol";
import {ISuccinctStaking} from "./interfaces/ISuccinctStaking.sol";
import {ISP1Verifier} from "./interfaces/ISP1Verifier.sol";
import {Initializable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {OwnableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {MerkleProof} from
    "../lib/openzeppelin-contracts/contracts/utils/cryptography/MerkleProof.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

/// @title SuccinctVApp
/// @author Succinct Labs
/// @notice Settlement layer for the Succinct Prover Network.
/// @dev Processes actions resulting from state transitions.
contract SuccinctVApp is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ISuccinctVApp
{
    using SafeERC20 for IERC20;

    /// @inheritdoc ISuccinctVApp
    address public override prove;

    /// @inheritdoc ISuccinctVApp
    address public override iProve;
    /// @inheritdoc ISuccinctVApp
    address public override staking;

    /// @inheritdoc ISuccinctVApp
    address public override verifier;

    /// @inheritdoc ISuccinctVApp
    address public override feeVault;

    /// @inheritdoc ISuccinctVApp
    bytes32 public override vappProgramVKey;

    /// @inheritdoc ISuccinctVApp
    uint64 public override blockNumber;

    /// @inheritdoc ISuccinctVApp
    uint64 public override maxActionDelay;

    /// @inheritdoc ISuccinctVApp
    uint256 public override minDepositAmount;

    /// @inheritdoc ISuccinctVApp
    uint256 public override protocolFeeBips;

    /// @inheritdoc ISuccinctVApp
    uint64 public override currentReceipt;

    /// @inheritdoc ISuccinctVApp
    uint64 public override finalizedReceipt;

    /// @inheritdoc ISuccinctVApp
    mapping(address => uint256) public override claimableWithdrawal;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => bytes32) public override roots;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => uint64) public override timestamps;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => Receipt) public override receipts;

    /// @inheritdoc ISuccinctVApp
    mapping(address => bool) public override usedSigners;

    mapping(address => address[]) internal delegatedSigners;

    /// @dev Modifier to ensure that the caller is the staking contract.
    modifier onlyStaking() {
        if (msg.sender != staking) revert NotStaking();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @custom:oz-upgrades-unsafe-allow-initializers
    function initialize(
        address _owner,
        address _prove,
        address _iProve,
        address _staking,
        address _verifier,
        address _feeVault,
        bytes32 _vappProgramVKey,
        uint64 _maxActionDelay,
        uint256 _protocolFeeBips
    ) external initializer {
        if (
            _owner == address(0) || _prove == address(0) || _staking == address(0)
                || _verifier == address(0) || _feeVault == address(0)
        ) {
            revert ZeroAddress();
        }

        __ReentrancyGuard_init();
        __Ownable_init(_owner);

        prove = _prove;
        iProve = _iProve;
        staking = _staking;
        verifier = _verifier;
        feeVault = _feeVault;
        vappProgramVKey = _vappProgramVKey;
        maxActionDelay = _maxActionDelay;
        protocolFeeBips = _protocolFeeBips;

        _updateStaking(_staking);
        _updateVerifier(_verifier);
        _updateFeeVault(_feeVault);
        _updateActionDelay(_maxActionDelay);
        _updateProtocolFeeBips(_protocolFeeBips);

        // Approve the $iPROVE contract to transfer $PROVE from this contract during prover withdrawal.
        IERC20(prove).approve(_iProve, type(uint256).max);

        emit Fork(_vappProgramVKey, 0, bytes32(0), bytes32(0));
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctVApp
    function root() public view override returns (bytes32) {
        return roots[blockNumber];
    }

    /// @inheritdoc ISuccinctVApp
    function timestamp() public view override returns (uint64) {
        return timestamps[blockNumber];
    }

    /// @inheritdoc ISuccinctVApp
    function hasDelegatedSigner(address _owner, address _signer)
        public
        view
        override
        returns (uint256)
    {
        address[] memory signers = delegatedSigners[_owner];
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == _signer) {
                return i;
            }
        }

        return type(uint256).max;
    }

    /// @inheritdoc ISuccinctVApp
    function getDelegatedSigners(address _owner)
        external
        view
        override
        returns (address[] memory)
    {
        return delegatedSigners[_owner];
    }

    /*//////////////////////////////////////////////////////////////
                                  CORE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctVApp
    function deposit(uint256 _amount) external override returns (uint64 receipt) {
        return _deposit(msg.sender, _amount);
    }

    /// @inheritdoc ISuccinctVApp
    function permitAndDeposit(
        address _from,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external override returns (uint64 receipt) {
        // Approve this contract to spend the $PROVE from the depositor.
        IERC20Permit(prove).permit(_from, address(this), _amount, _deadline, _v, _r, _s);

        return _deposit(_from, _amount);
    }

    /// @inheritdoc ISuccinctVApp
    function requestWithdraw(address _to, uint256 _amount) external override returns (uint64 receipt) {
        return _requestWithdraw(msg.sender, _to, _amount);
    }

    /// @inheritdoc ISuccinctVApp
    function finishWithdrawal(address _to) external override returns (uint256 amount) {
        // Validate.
        amount = claimableWithdrawal[_to];
        if (amount == 0) revert NoWithdrawalToClaim();

        // Update the state.
        claimableWithdrawal[_to] = 0;

        // Transfer the withdrawal.
        //
        // If the `_to` is a prover vault, we need to first deposit it to get $iPROVE and then
        // transfer the $iPROVE to the prover vault. This splits the $PROVE amount amongst all
        // of the prover stakers.
        //
        // Otherwise if the `_to` is not a prover vault, we can just transfer the $PROVE directly.
        if(ISuccinctStaking(staking).isProver(_to)) {
            // Deposit $PROVE to mint $iPROVE, sending it to this contract.
            uint256 iPROVE = IERC4626(iProve).deposit(amount, address(this));

            // Transfer the $iPROVE from this contract to the prover vault.
            IERC20(iProve).safeTransfer(_to, iPROVE);
        } else {
            // Transfer the $PROVE from this contract to the `_to` address.
            IERC20(prove).safeTransfer(_to, amount);
        }

        emit Withdrawal(_to, amount);
    }

    /// @inheritdoc ISuccinctVApp
    function addDelegatedSigner(address _signer) external returns (uint64 receipt) {
        return _addDelegatedSigner(msg.sender, _signer);
    }

    /// @inheritdoc ISuccinctVApp
    function addDelegatedSignerForProver(address _owner, address _signer) external onlyStaking returns (uint64 receipt) {
        return _addDelegatedSigner(_owner, _signer);
    }

    /// @inheritdoc ISuccinctVApp
    function removeDelegatedSigner(address _signer) external returns (uint64 receipt) {
        return _removeDelegatedSigner(msg.sender, _signer);
    }
    
    /// @inheritdoc ISuccinctVApp
    function updateState(bytes calldata _publicValues, bytes calldata _proofBytes)
        public
        nonReentrant
        returns (uint64, bytes32, bytes32)
    {
        // Verify the proof.
        ISP1Verifier(verifier).verifyProof(vappProgramVKey, _publicValues, _proofBytes);
        PublicValuesStruct memory publicValues = abi.decode(_publicValues, (PublicValuesStruct));
        if (publicValues.newRoot == bytes32(0)) revert InvalidRoot();

        // Verify the old root.
        if (blockNumber != 0 && roots[blockNumber] != publicValues.oldRoot) {
            revert InvalidOldRoot();
        }

        // Assert that the timestamp is not in the future and is increasing.
        if (publicValues.timestamp > block.timestamp) revert InvalidTimestamp();
        if (blockNumber != 0 && timestamps[blockNumber] > publicValues.timestamp) {
            revert TimestampInPast();
        }

        // Update the state root.
        uint64 _block = ++blockNumber;
        roots[_block] = publicValues.newRoot;
        timestamps[_block] = publicValues.timestamp;

        // Commit the actions.
        _handleActions(publicValues);

        emit Block(_block, publicValues.newRoot, publicValues.oldRoot);

        return (_block, publicValues.newRoot, publicValues.oldRoot);
    }

    /*//////////////////////////////////////////////////////////////
                                 OWNER
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctVApp
    function fork(
        bytes32 _vkey,
        bytes32 _newOldRoot,
        bytes calldata _publicValues,
        bytes calldata _proofBytes
    ) external override onlyOwner returns (uint64, bytes32, bytes32) {
        // Update the vkey.
        vappProgramVKey = _vkey;

        // Update the root and produce a new block.
        bytes32 _oldRoot = bytes32(0);
        uint64 _block = blockNumber;
        if (_block != 0) {
            _oldRoot = roots[_block];
        }
        roots[++_block] = _newOldRoot;

        emit Block(_block, _newOldRoot, _oldRoot);
        emit Fork(vappProgramVKey, _block, _newOldRoot, _oldRoot);

        return updateState(_publicValues, _proofBytes);
    }

    /// @inheritdoc ISuccinctVApp
    function updateStaking(address _staking) external override onlyOwner {
        _updateStaking(_staking);
    }

    /// @inheritdoc ISuccinctVApp
    function updateVerifier(address _verifier) external override onlyOwner {
        _updateVerifier(_verifier);
    }

    /// @inheritdoc ISuccinctVApp
    function updateFeeVault(address _feeVault) external override onlyOwner {
        _updateFeeVault(_feeVault);
    }

    /// @inheritdoc ISuccinctVApp
    function updateActionDelay(uint64 _maxActionDelay) external override onlyOwner {
        _updateActionDelay(_maxActionDelay);
    }

    /// @inheritdoc ISuccinctVApp
    function updateMinDepositAmount(uint256 _amount) external override onlyOwner {
        _updateMinDepositAmount(_amount);
    }

    /// @inheritdoc ISuccinctVApp
    function updateProtocolFeeBips(uint256 _protocolFeeBips) external override onlyOwner {
        _updateProtocolFeeBips(_protocolFeeBips);
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Credits a deposit receipt and transfers $PROVE from the sender to the VApp.
    function _deposit(address _from, uint256 _amount) internal returns (uint64 receipt) {
        // Validate.
        if (_amount < minDepositAmount) {
            revert TransferBelowMinimum();
        }

        // Create the receipt.
        bytes memory data =
            abi.encode(DepositAction({account: _from, amount: _amount, token: prove}));
        receipt = _createReceipt(ActionType.Deposit, data);

        // Transfer $PROVE from the sender to the VApp.
        IERC20(prove).safeTransferFrom(_from, address(this), _amount);
    }

    /// @dev Credits a withdrawal receipt.
    function _requestWithdraw(address _from, address _to, uint256 _amount) internal returns (uint64 receipt) {
        // Validate.
        if (_to == address(0)) revert ZeroAddress();
        if (_amount < minDepositAmount) {
            revert TransferBelowMinimum();
        }

        // Create the receipt.
        bytes memory data = abi.encode(
            WithdrawAction({account: _from, amount: _amount, to: _to, token: prove})
        );
        receipt = _createReceipt(ActionType.Withdraw, data);
    }

    function _addDelegatedSigner(address _owner, address _signer) internal returns (uint64 receipt) {
        // Validate.
        if (_signer == address(0)) revert ZeroAddress();
        if (usedSigners[_signer]) revert InvalidSigner();
        if (!ISuccinctStaking(staking).hasProver(_owner)) revert InvalidSigner();
        if (ISuccinctStaking(staking).isProver(_signer)) revert InvalidSigner();
        if (ISuccinctStaking(staking).hasProver(_signer)) revert InvalidSigner();

        // Create the receipt.
        bytes memory data = abi.encode(AddSignerAction({owner: _owner, signer: _signer}));
        receipt = _createReceipt(ActionType.AddSigner, data);

        // Update the state.
        usedSigners[_signer] = true;
        delegatedSigners[_owner].push(_signer);
    }

    function _removeDelegatedSigner(address _owner, address _signer) internal returns (uint64 receipt) {
        // Validate.
        uint256 index = hasDelegatedSigner(_owner, _signer);
        if (index == type(uint256).max) revert InvalidSigner();
        if (!usedSigners[_signer]) revert InvalidSigner();

        // Create the receipt.
        bytes memory data = abi.encode(RemoveSignerAction({owner: _owner, signer: _signer}));
        receipt = _createReceipt(ActionType.RemoveSigner, data);

        // Update the state.
        usedSigners[_signer] = false;
        delegatedSigners[_owner][index] =
            delegatedSigners[_owner][delegatedSigners[_owner].length - 1];
        delegatedSigners[_owner].pop();
    }
    
    /// @dev Creates a receipt for an action.
    function _createReceipt(ActionType _actionType, bytes memory _data)
        internal
        returns (uint64 receipt)
    {
        receipt = ++currentReceipt;
        receipts[receipt] = Receipt({
            action: _actionType,
            status: ReceiptStatus.Pending,
            timestamp: uint64(block.timestamp),
            data: _data
        });

        emit ReceiptPending(receipt, _actionType, _data);
    }

    /// @dev Handles committed actions, reverts if the actions are invalid
    function _handleActions(PublicValuesStruct memory _publicValues) internal {
        // Validate the actions.
        Actions.validate(
            receipts,
            _publicValues.actions,
            finalizedReceipt,
            currentReceipt,
            uint64(block.timestamp),
            maxActionDelay
        );

        // Execute the actions.
        ActionsInternal memory decoded = Actions.decode(_publicValues.actions);
        _depositActions(decoded.deposits);
        _requestWithdrawActions(decoded.withdrawals);
        _addSignerActions(decoded.addSigners);
        _removeSignerActions(decoded.removeSigners);

        // Update the last finalized receipt.
        if (decoded.lastReceipt != 0) {
            finalizedReceipt = decoded.lastReceipt;
        }
    }

    /// @dev Handles deposit actions.
    function _depositActions(DepositInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            receipts[_actions[i].action.receipt].status = _actions[i].action.status;

            emit ReceiptCompleted(
                _actions[i].action.receipt, ActionType.Deposit, _actions[i].action.data
            );
        }
    }

    /// @dev Handles withdraw actions.
    function _requestWithdrawActions(WithdrawInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            // Only update if there is a corresponding receipt.
            if (_actions[i].action.receipt != 0) {
                receipts[_actions[i].action.receipt].status = _actions[i].action.status;

                if (_actions[i].action.status == ReceiptStatus.Failed) {
                    emit ReceiptFailed(
                        _actions[i].action.receipt, ActionType.Withdraw, _actions[i].action.data
                    );
                }
            }

            // Handle the action status.
            if (_actions[i].action.status == ReceiptStatus.Completed) {
                // Process the withdrawal.
                _processWithdraw(_actions[i].data.to, _actions[i].data.amount);

                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.Withdraw, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Handles add signer actions.
    function _addSignerActions(AddSignerInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            receipts[_actions[i].action.receipt].status = _actions[i].action.status;

            if (_actions[i].action.status == ReceiptStatus.Completed) {
                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.AddSigner, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Handles remove signer actions.
    function _removeSignerActions(RemoveSignerInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            receipts[_actions[i].action.receipt].status = _actions[i].action.status;

            if (_actions[i].action.status == ReceiptStatus.Completed) {
                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.RemoveSigner, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Processes a withdrawal by creating a claim for the amount.
    function _processWithdraw(address _to, uint256 _amount) internal {
        // Update the state.
        claimableWithdrawal[_to] += _amount;
    }

    /// @dev Updates the staking contract.
    function _updateStaking(address _staking) internal {
        emit StakingUpdate(staking, _staking);

        staking = _staking;
    }

    /// @dev Updates the verifier.
    function _updateVerifier(address _verifier) internal {
        emit VerifierUpdate(verifier, _verifier);

        verifier = _verifier;
    }

    /// @dev Updates the fee vault.
    function _updateFeeVault(address _feeVault) internal {
        emit FeeVaultUpdate(feeVault, _feeVault);

        feeVault = _feeVault;
    }

    /// @dev Updates the action delay.
    function _updateActionDelay(uint64 _maxActionDelay) internal {
        emit MaxActionDelayUpdate(maxActionDelay, _maxActionDelay);

        maxActionDelay = _maxActionDelay;
    }

    /// @dev Updates the minimum amount for deposit/withdraw operations.
    function _updateMinDepositAmount(uint256 _amount) internal {
        emit MinDepositAmountUpdate(minDepositAmount, _amount);

        minDepositAmount = _amount;
    }

    /// @dev Updates the protocol fee in basis points.
    function _updateProtocolFeeBips(uint256 _protocolFeeBips) internal {
        emit ProtocolFeeBipsUpdate(protocolFeeBips, _protocolFeeBips);

        protocolFeeBips = _protocolFeeBips;
    }

    /// @dev Authorizes an ERC1967 proxy upgrade to a new implementation contract.
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
