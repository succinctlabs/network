// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    Receipt,
    Actions,
    ActionsInternal,
    DepositInternal,
    WithdrawInternal,
    AddSignerInternal,
    RemoveSignerInternal,
    SlashInternal,
    RewardInternal,
    ProverStateInternal,
    FeeUpdateInternal
} from "./libraries/Actions.sol";
import {
    PublicValuesStruct,
    ReceiptStatus,
    Action,
    ActionType,
    DepositAction,
    WithdrawAction,
    AddSignerAction,
    RemoveSignerAction,
    SlashAction,
    RewardAction,
    ProverStateAction,
    FeeUpdateAction
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
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

/// @title SuccinctVApp
/// @author Succinct Labs
/// @notice Settlement layer for the vApp, processes deposits and withdrawals resulting from state transitions.
contract SuccinctVApp is
    Initializable,
    ReentrancyGuardUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ISuccinctVApp
{
    using SafeERC20 for ERC20;

    /// @inheritdoc ISuccinctVApp
    uint256 public constant override FEE_UNIT = 10000;

    /// @inheritdoc ISuccinctVApp
    address public override prove;

    /// @inheritdoc ISuccinctVApp
    address public override staking;

    /// @inheritdoc ISuccinctVApp
    address public override verifier;

    /// @inheritdoc ISuccinctVApp
    bytes32 public override vappProgramVKey;

    /// @inheritdoc ISuccinctVApp
    uint64 public override blockNumber;

    /// @inheritdoc ISuccinctVApp
    uint64 public override maxActionDelay;

    /// @inheritdoc ISuccinctVApp
    uint64 public override freezeDuration;

    /// @inheritdoc ISuccinctVApp
    uint256 public override minimumDeposit;

    /// @inheritdoc ISuccinctVApp
    uint256 public override totalDeposits;

    /// @inheritdoc ISuccinctVApp
    uint256 public override totalPendingWithdrawals;

    /// @inheritdoc ISuccinctVApp
    uint64 public override currentReceipt;

    /// @inheritdoc ISuccinctVApp
    uint64 public override finalizedReceipt;

    /// @inheritdoc ISuccinctVApp
    mapping(address => uint256) public override withdrawalClaims;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => bytes32) public override roots;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => uint64) public override timestamps;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => Receipt) public override receipts;

    /// @inheritdoc ISuccinctVApp
    mapping(address => bool) public override usedSigners;

    mapping(address => address[]) internal delegatedSigners;

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
        address _staking,
        address _verifier,
        bytes32 _vappProgramVKey,
        uint64 _maxActionDelay,
        uint64 _freezeDuration
    ) external initializer {
        if (
            _owner == address(0) || _prove == address(0) || _staking == address(0)
                || _verifier == address(0)
        ) {
            revert ZeroAddress();
        }

        __ReentrancyGuard_init();
        __Ownable_init(_owner);

        prove = _prove;
        staking = _staking;
        verifier = _verifier;
        vappProgramVKey = _vappProgramVKey;
        maxActionDelay = _maxActionDelay;
        freezeDuration = _freezeDuration;

        _updateStaking(_staking);
        _updateVerifier(_verifier);
        _updateActionDelay(_maxActionDelay);
        _updateFreezeDuration(_freezeDuration);

        emit Fork(_vappProgramVKey, 0, bytes32(0), bytes32(0));
    }

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
    function deposit(uint256 _amount)
        external
        override
        returns (uint64 receipt)
    {
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
        IERC20Permit(prove).permit(_from, address(this), _amount, _deadline, _v, _r, _s);

        return _deposit(_from, _amount);
    }

    /// @inheritdoc ISuccinctVApp
    function withdraw(address _to, uint256 _amount) external override returns (uint64 receipt) {
        // Validate.
        if (_to == address(0)) revert ZeroAddress();
        if (_amount < minimumDeposit) {
            revert TransferBelowMinimum();
        }

        // Create the receipt.
        bytes memory data = abi.encode(
            WithdrawAction({account: msg.sender, amount: _amount, to: _to, token: prove})
        );
        receipt = _createReceipt(ActionType.Withdraw, data);
    }

    /// @inheritdoc ISuccinctVApp
    function claimWithdrawal(address _to) external override returns (uint256 amount) {
        // Validate.
        amount = withdrawalClaims[_to];
        if (amount == 0) revert NoWithdrawalToClaim();

        // Update the state.
        totalPendingWithdrawals -= amount;
        withdrawalClaims[_to] = 0;

        // Transfer the withdrawal.
        ERC20(prove).safeTransfer(_to, amount);

        emit WithdrawalClaimed(_to, msg.sender, amount);
    }

    /// @inheritdoc ISuccinctVApp
    function emergencyWithdraw(uint256 _amount, bytes32[] calldata _proof) external {
        // Validate.
        if (_proof.length == 0) revert InvalidProof();
        if (block.timestamp < timestamp() + freezeDuration) revert NotFrozen();
        if (_amount < minimumDeposit) {
            revert TransferBelowMinimum();
        }

        // Verify the proof.
        bytes32 leaf = sha256(abi.encodePacked(msg.sender, _amount));
        bytes32 root_ = root();
        bool isValid = MerkleProof.verifyCalldata(_proof, root_, leaf, _hashPair);
        if (!isValid) revert ProofFailed();

        // Process the withdrawal.
        _processWithdraw(msg.sender, _amount);

        emit EmergencyWithdrawal(msg.sender, _amount, root_);
    }

    /// @inheritdoc ISuccinctVApp
    function addDelegatedSigner(address _signer) external returns (uint64 receipt) {
        // Validate.
        if (_signer == address(0)) revert ZeroAddress();
        if (usedSigners[_signer]) revert InvalidSigner();
        if (!ISuccinctStaking(staking).hasProver(msg.sender)) revert InvalidSigner();
        if (ISuccinctStaking(staking).isProver(_signer)) revert InvalidSigner();
        if (ISuccinctStaking(staking).hasProver(_signer)) revert InvalidSigner();

        // Create the receipt.
        bytes memory data = abi.encode(AddSignerAction({owner: msg.sender, signer: _signer}));
        receipt = _createReceipt(ActionType.AddSigner, data);

        // Update the state.
        usedSigners[_signer] = true;
        delegatedSigners[msg.sender].push(_signer);
    }

    /// @inheritdoc ISuccinctVApp
    function removeDelegatedSigner(address _signer) external returns (uint64 receipt) {
        // Validate.
        uint256 index = hasDelegatedSigner(msg.sender, _signer);
        if (index == type(uint256).max) revert InvalidSigner();
        if (!usedSigners[_signer]) revert InvalidSigner();

        // Create the receipt.
        bytes memory data = abi.encode(RemoveSignerAction({owner: msg.sender, signer: _signer}));
        receipt = _createReceipt(ActionType.RemoveSigner, data);

        // Update the state.
        usedSigners[_signer] = false;
        delegatedSigners[msg.sender][index] =
            delegatedSigners[msg.sender][delegatedSigners[msg.sender].length - 1];
        delegatedSigners[msg.sender].pop();
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
    function updateActionDelay(uint64 _maxActionDelay) external override onlyOwner {
        _updateActionDelay(_maxActionDelay);
    }

    /// @inheritdoc ISuccinctVApp
    function updateFreezeDuration(uint64 _freezeDuration) external override onlyOwner {
        _updateFreezeDuration(_freezeDuration);
    }

    /// @inheritdoc ISuccinctVApp
    function setMinimumDeposit(uint256 _amount) external override onlyOwner {
        _setMinimumDeposit(_amount);
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Credits a deposit receipt, transfers $PROVE from the sender to the VApp.
    function _deposit(address _from, uint256 _amount)
        internal
        returns (uint64 receipt)
    {
        // Validate.
        if (_amount < minimumDeposit) {
            revert TransferBelowMinimum();
        }

        // Create the receipt.
        bytes memory data = abi.encode(DepositAction({account: _from, amount: _amount, token: prove}));
        receipt = _createReceipt(ActionType.Deposit, data);

        // Update the state.
        totalDeposits += _amount;

        // Transfer $PROVE from the sender to the VApp.
        ERC20(prove).safeTransferFrom(_from, address(this), _amount);
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
        uint64 timestamp_ = uint64(block.timestamp);
        uint64 actionDelay_ = maxActionDelay;
        Actions.validate(
            receipts,
            _publicValues.actions,
            finalizedReceipt,
            currentReceipt,
            timestamp_,
            actionDelay_
        );

        // Execute the actions.
        ActionsInternal memory decoded = Actions.decode(_publicValues.actions);
        _depositActions(decoded.deposits);
        _withdrawActions(decoded.withdrawals);
        _addSignerActions(decoded.addSigners);
        _removeSignerActions(decoded.removeSigners);
        _slashActions(decoded.slashes);
        _rewardActions(decoded.rewards);
        _proverStateActions(decoded.proverStates);
        _feeUpdateActions(decoded.feeUpdates);

        // Update the last finalized receipt
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
    function _withdrawActions(WithdrawInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            // Only update if there is a corresponding receipt
            if (_actions[i].action.receipt != 0) {
                receipts[_actions[i].action.receipt].status = _actions[i].action.status;

                if (_actions[i].action.status == ReceiptStatus.Failed) {
                    emit ReceiptFailed(
                        _actions[i].action.receipt, ActionType.Withdraw, _actions[i].action.data
                    );
                }
            }

            // Handle the action status
            if (_actions[i].action.status == ReceiptStatus.Completed) {
                // Process the withdrawal
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

    /// @dev Handles slash actions.
    function _slashActions(SlashInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            if (_actions[i].action.status == ReceiptStatus.Completed) {
                ISuccinctStaking(staking).requestSlash(
                    _actions[i].data.prover, _actions[i].data.amount
                );

                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.Slash, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Handles reward actions.
    function _rewardActions(RewardInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            if (_actions[i].action.status == ReceiptStatus.Completed) {
                // Transfer $PROVE from VApp to staking contract.
                ERC20(prove).safeTransfer(staking, _actions[i].data.amount);

                // Call reward function on staking contract.
                ISuccinctStaking(staking).reward(_actions[i].data.prover, _actions[i].data.amount);

                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.Reward, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Handles prover state actions.
    function _proverStateActions(ProverStateInternal[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            if (_actions[i].action.status == ReceiptStatus.Completed) {
                // Verify array lengths match.
                if (_actions[i].data.provers.length != _actions[i].data.proveBalances.length) {
                    revert ArrayLengthMismatch();
                }

                // Verify each prover's on-chain balance matches the asserted balance.
                for (uint256 j = 0; j < _actions[i].data.provers.length; j++) {
                    address prover = _actions[i].data.provers[j];
                    uint256 assertedProveBalance = _actions[i].data.proveBalances[j];

                    // Check the $PROVE token balance.
                    uint256 actualProveBalance = ERC20(prove).balanceOf(prover);
                    if (actualProveBalance != assertedProveBalance) {
                        revert BalanceMismatch();
                    }
                }

                emit ReceiptCompleted(
                    _actions[i].action.receipt, ActionType.ProverState, _actions[i].action.data
                );
            }
        }
    }

    /// @dev Processes a withdrawal by creating a claim for the amount.
    function _processWithdraw(address _to, uint256 _amount) internal {
        // Update the state.
        totalPendingWithdrawals += _amount;
        withdrawalClaims[_to] += _amount;
        totalDeposits -= _amount;
    }

    /// @dev Updates the staking contract.
    function _updateStaking(address _staking) internal {
        staking = _staking;

        emit StakingUpdate(_staking);
    }

    /// @dev Updates the verifier.
    function _updateVerifier(address _verifier) internal {
        verifier = _verifier;

        emit VerifierUpdate(_verifier);
    }

    /// @dev Updates the action delay.
    function _updateActionDelay(uint64 _maxActionDelay) internal {
        maxActionDelay = _maxActionDelay;

        emit MaxActionDelayUpdate(_maxActionDelay);
    }

    /// @dev Updates the freeze duration.
    function _updateFreezeDuration(uint64 _freezeDuration) internal {
        freezeDuration = _freezeDuration;

        emit FreezeDurationUpdate(_freezeDuration);
    }

    /// @dev Sets the minimum amount for deposit/withdraw operations.
    function _setMinimumDeposit(uint256 _amount) internal {
        minimumDeposit = _amount;

        emit MinimumDepositUpdate(_amount);
    }

    /// @dev Handles fee update actions.
    function _feeUpdateActions(FeeUpdateInternal[] memory _actions) internal {}

    /// @dev Hashes a pair of bytes32 values using SHA-256.
    function _hashPair(bytes32 _a, bytes32 _b) internal pure returns (bytes32) {
        return (_a < _b) ? sha256(abi.encodePacked(_a, _b)) : sha256(abi.encodePacked(_b, _a));
    }

    /// @dev Authorizes an ERC1967 proxy upgrade to a new implementation contract.
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
