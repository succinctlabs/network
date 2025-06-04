// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Actions} from "./libraries/Actions.sol";
import {
    PublicValuesStruct,
    TransactionStatus,
    Receipt,
    Transaction,
    TransactionVariant,
    DepositTransaction,
    WithdrawTransaction,
    CreateProverTransaction,
    ReceiptsInternal,
    DepositReceipt,
    WithdrawReceipt,
    CreateProverReceipt
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
    bytes32 public override vappProgramVKey;

    /// @inheritdoc ISuccinctVApp
    uint64 public override blockNumber;

    /// @inheritdoc ISuccinctVApp
    uint256 public override minDepositAmount;

    /// @inheritdoc ISuccinctVApp
    uint64 public override currentOnchainTx;

    /// @inheritdoc ISuccinctVApp
    uint64 public override finalizedOnchainTx;

    /// @inheritdoc ISuccinctVApp
    mapping(address => uint256) public override claimableWithdrawal;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => bytes32) public override roots;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => uint64) public override timestamps;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => Transaction) public override transactions;

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
        bytes32 _vappProgramVKey,
        uint64 _freezeDuration,
        bytes32 _genesisStateRoot,
        uint64 _genesisTimestamp
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
        iProve = _iProve;
        staking = _staking;
        verifier = _verifier;
        vappProgramVKey = _vappProgramVKey;

        // Set the genesis state root.
        roots[0] = _genesisStateRoot;
        timestamps[0] = _genesisTimestamp;
        blockNumber = 0;

        _updateStaking(_staking);
        _updateVerifier(_verifier);

        // Approve the $iPROVE contract to transfer $PROVE from this contract during prover withdrawal.
        IERC20(prove).approve(_iProve, type(uint256).max);

        emit Fork(_vappProgramVKey, blockNumber, _genesisStateRoot, bytes32(0));
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
    function requestWithdraw(address _to, uint256 _amount)
        external
        override
        returns (uint64 receipt)
    {
        // TODO(jtguibas): maybe consider simplifying this in the future
        // Validate.
        if (_to == address(0)) revert ZeroAddress();
        if (_amount < minDepositAmount) revert TransferBelowMinimum();

        // If the `_to` is a prover vault, then anyone can do it. Otherwise, only `_to` can trigger
        // the withdrawal.
        if (msg.sender != _to) {
            if (!ISuccinctStaking(staking).isProver(_to)) revert CannotWithdrawToDifferentAddress();
        }

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
        if (ISuccinctStaking(staking).isProver(_to)) {
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
    function createProver(address _prover, address _owner, uint256 _stakerFeeBips)
        external
        onlyStaking
        returns (uint64 receipt)
    {
        // Validate.
        if (_owner == address(0)) revert ZeroAddress();
        if (_owner != ISuccinctStaking(staking).ownerOf(_prover)) revert ProverNotOwned();

        // Create the receipt.
        bytes memory data = abi.encode(CreateProverTransaction({prover: _prover, owner: _owner, stakerFeeBips: _stakerFeeBips}));
        receipt = _createTransaction(TransactionVariant.Prover, data);
    }

    /// @inheritdoc ISuccinctVApp
    function step(bytes calldata _publicValues, bytes calldata _proofBytes)
        public
        nonReentrant
        returns (uint64, bytes32, bytes32)
    {
        // Verify the proof.
        ISP1Verifier(verifier).verifyProof(vappProgramVKey, _publicValues, _proofBytes);
        PublicValuesStruct memory publicValues = abi.decode(_publicValues, (PublicValuesStruct));
        if (publicValues.newRoot == bytes32(0)) revert InvalidRoot();

        // Verify the old root.
        if (roots[blockNumber] != publicValues.oldRoot) {
            revert InvalidOldRoot();
        }

        // Assert that the timestamp is not in the future and is increasing.
        if (publicValues.timestamp > block.timestamp) revert InvalidTimestamp();
        if (timestamps[blockNumber] > publicValues.timestamp) {
            revert TimestampInPast();
        }

        // Update the state root.
        uint64 _block = ++blockNumber;
        roots[_block] = publicValues.newRoot;
        timestamps[_block] = publicValues.timestamp;

        emit Block(_block, publicValues.newRoot, publicValues.oldRoot);

        // Commit the actions.
        _handleActions(publicValues);

        return (_block, publicValues.newRoot, publicValues.oldRoot);
    }

    /*//////////////////////////////////////////////////////////////
                                 OWNER
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctVApp
    function fork(
        bytes32 _vkey,
        bytes32 _newRoot
    ) external override onlyOwner returns (uint64, bytes32, bytes32) {
        // Update the vkey.
        vappProgramVKey = _vkey;

        // Get the old root.
        bytes32 _oldRoot = roots[blockNumber];

        // Update the root and produce a new block.
        uint64 _block = ++blockNumber;
        roots[_block] = _newRoot;

        emit Block(_block, _newRoot, _oldRoot);
        emit Fork(vappProgramVKey, _block, _newRoot, _oldRoot);

        return (_block, _newRoot, _oldRoot);
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
    function updateMinDepositAmount(uint256 _amount) external override onlyOwner {
        _updateMinDepositAmount(_amount);
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
            abi.encode(DepositTransaction({account: _from, amount: _amount}));
        receipt = _createTransaction(TransactionVariant.Deposit, data);

        // Transfer $PROVE from the sender to the VApp.
        IERC20(prove).safeTransferFrom(_from, address(this), _amount);
    }

    /// @dev Credits a withdrawal receipt.
    function _requestWithdraw(address _from, address _to, uint256 _amount)
        internal
        returns (uint64 receipt)
    {
        // Validate.
        if (_to == address(0)) revert ZeroAddress();
        if (_amount < minDepositAmount) {
            revert TransferBelowMinimum();
        }

        // Create the receipt.
        bytes memory data =
            abi.encode(WithdrawTransaction({account: _from, to: _to, amount: _amount}));
        receipt = _createTransaction(TransactionVariant.Withdraw, data);
    }

    /// @dev Creates a receipt for an action.
    function _createTransaction(TransactionVariant _transactionVariant, bytes memory _data)
        internal
        returns (uint64 onchainTx)
    {
        onchainTx = ++currentOnchainTx;
        transactions[onchainTx] = Transaction({
            variant: _transactionVariant,
            status: TransactionStatus.Pending,
            onchainTx: onchainTx,
            data: _data
        });

        emit TransactionPending(onchainTx, _transactionVariant, _data);
    }

    /// @dev Handles committed actions, reverts if the actions are invalid
    function _handleActions(PublicValuesStruct memory _publicValues) internal {
        // Validate the actions.
        Actions.validate(
            transactions,
            _publicValues.receipts,
            finalizedOnchainTx,
            currentOnchainTx,
            uint64(block.timestamp)
        );

        // Execute the actions.
        ReceiptsInternal memory decoded = Actions.decode(_publicValues.receipts);
        _depositActions(decoded.deposits);
        _requestWithdrawActions(decoded.withdrawals);
        _setProverActions(decoded.provers);

        // Update the last finalized receipt.
        finalizedOnchainTx = decoded.lastTxId;
    }

    /// @dev Handles deposit actions.
    function _depositActions(DepositReceipt[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            transactions[_actions[i].receipt.onchainTx].status = _actions[i].receipt.status;

            emit TransactionCompleted(
                _actions[i].receipt.onchainTx, TransactionVariant.Deposit, _actions[i].receipt.data
            );
        }
    }

    /// @dev Handles withdraw actions.
    function _requestWithdrawActions(WithdrawReceipt[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            // Only update if there is a corresponding receipt.
            if (_actions[i].receipt.onchainTx != 0) {
                transactions[_actions[i].receipt.onchainTx].status = _actions[i].receipt.status;

                if (_actions[i].receipt.status == TransactionStatus.Failed) {
                    emit TransactionFailed(
                        _actions[i].receipt.onchainTx, TransactionVariant.Withdraw, _actions[i].receipt.data
                    );
                }
            }

            // Handle the action status.
            if (_actions[i].receipt.status == TransactionStatus.Completed) {
                // Process the withdrawal.
                _processWithdraw(_actions[i].data.to, _actions[i].data.amount);

                emit TransactionCompleted(
                    _actions[i].receipt.onchainTx, TransactionVariant.Withdraw, _actions[i].receipt.data
                );
            }
        }
    }

    /// @dev Handles add signer actions.
    function _setProverActions(CreateProverReceipt[] memory _actions) internal {
        for (uint64 i = 0; i < _actions.length; i++) {
            transactions[_actions[i].receipt.onchainTx].status = _actions[i].receipt.status;

            if (_actions[i].receipt.status == TransactionStatus.Completed) {

                emit TransactionCompleted(
                    _actions[i].receipt.onchainTx,
                    TransactionVariant.Prover,
                    _actions[i].receipt.data
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

    /// @dev Updates the minimum amount for deposit/withdraw operations.
    function _updateMinDepositAmount(uint256 _amount) internal {
        emit MinDepositAmountUpdate(minDepositAmount, _amount);

        minDepositAmount = _amount;
    }

    /// @dev Authorizes an ERC1967 proxy upgrade to a new implementation contract.
    function _authorizeUpgrade(address _newImplementation) internal override onlyOwner {}
}
