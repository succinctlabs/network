// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Receipts} from "./libraries/Receipts.sol";
import {
    StepPublicValues,
    TransactionStatus,
    Receipt,
    Transaction,
    TransactionVariant,
    Deposit,
    Withdraw,
    CreateProver
} from "./libraries/PublicValues.sol";
import {ISuccinctVApp} from "./interfaces/ISuccinctVApp.sol";
import {ISuccinctStaking} from "./interfaces/ISuccinctStaking.sol";
import {ISP1Verifier} from "../lib/sp1-contracts/contracts/src/ISP1Verifier.sol";
import {Initializable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
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
import {PausableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

/// @title SuccinctVApp
/// @author Succinct Labs
/// @notice Settlement layer for the Succinct Prover Network.
/// @dev Processes actions resulting from state transitions.
contract SuccinctVApp is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
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
    uint64 public override currentOnchainTxId;

    /// @inheritdoc ISuccinctVApp
    uint64 public override finalizedOnchainTxId;

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
        bytes32 _genesisStateRoot,
        uint64 _genesisTimestamp
    ) external initializer {
        if (
            _owner == address(0) || _prove == address(0) || _iProve == address(0)
                || _staking == address(0) || _verifier == address(0)
        ) {
            revert ZeroAddress();
        }

        __Ownable_init(_owner);

        prove = _prove;
        iProve = _iProve;
        staking = _staking;
        verifier = _verifier;
        vappProgramVKey = _vappProgramVKey;

        // Set the genesis state root.
        roots[0] = _genesisStateRoot;
        timestamps[0] = _genesisTimestamp;

        _updateStaking(_staking);
        _updateVerifier(_verifier);

        // Approve the $iPROVE contract to transfer $PROVE from this contract during prover withdrawal.
        IERC20(prove).approve(_iProve, type(uint256).max);

        // Emit the events.
        emit Fork(0, bytes32(0), _vappProgramVKey);
        emit Block(0, bytes32(0), _genesisStateRoot);
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
    function deposit(uint256 _amount) external override whenNotPaused returns (uint64 receipt) {
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
    ) external override whenNotPaused returns (uint64 receipt) {
        // Approve this contract to spend the $PROVE from the depositor.
        IERC20Permit(prove).permit(_from, address(this), _amount, _deadline, _v, _r, _s);

        return _deposit(_from, _amount);
    }

    /// @inheritdoc ISuccinctVApp
    function requestWithdraw(address _to, uint256 _amount)
        external
        override
        whenNotPaused
        returns (uint64 receipt)
    {
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
    function finishWithdraw(address _to) external override whenNotPaused returns (uint256 amount) {
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
        whenNotPaused
        returns (uint64 receipt)
    {
        // Validate.
        if (_owner == address(0)) revert ZeroAddress();
        if (_owner != ISuccinctStaking(staking).ownerOf(_prover)) revert ProverNotOwned();

        // Create the receipt.
        bytes memory data = abi.encode(
            CreateProver({prover: _prover, owner: _owner, stakerFeeBips: _stakerFeeBips})
        );
        receipt = _createTransaction(TransactionVariant.CreateProver, data);
    }

    /// @inheritdoc ISuccinctVApp
    function step(bytes calldata _publicValues, bytes calldata _proofBytes)
        external
        whenNotPaused
        returns (uint64, bytes32, bytes32)
    {
        // Verify the proof.
        ISP1Verifier(verifier).verifyProof(vappProgramVKey, _publicValues, _proofBytes);
        StepPublicValues memory publicValues = abi.decode(_publicValues, (StepPublicValues));
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
        uint64 newBlock = ++blockNumber;
        roots[newBlock] = publicValues.newRoot;
        timestamps[newBlock] = publicValues.timestamp;

        // Handle the receipts.
        _handleReceipts(publicValues);

        // Emit the event.
        emit Block(newBlock, publicValues.oldRoot, publicValues.newRoot);

        return (newBlock, publicValues.oldRoot, publicValues.newRoot);
    }

    /*//////////////////////////////////////////////////////////////
                                 OWNER
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctVApp
    function fork(bytes32 _vkey, bytes32 _root)
        external
        override
        onlyOwner
        returns (uint64, bytes32, bytes32)
    {
        // Save the old vkey for event.
        bytes32 oldVkey = vappProgramVKey;

        // Update the vkey.
        vappProgramVKey = _vkey;

        // Get the old root.
        bytes32 oldRoot = roots[blockNumber];

        // Update the root and produce a new block.
        uint64 newBlock = ++blockNumber;
        roots[newBlock] = _root;

        // Emit the events.
        emit Fork(newBlock, oldVkey, _vkey);
        emit Block(newBlock, oldRoot, _root);

        return (newBlock, oldRoot, _root);
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

    /// @inheritdoc ISuccinctVApp
    function pause() external override onlyOwner whenNotPaused {
        _pause();
    }

    /// @inheritdoc ISuccinctVApp
    function unpause() external override onlyOwner whenPaused {
        _unpause();
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
        bytes memory data = abi.encode(Deposit({account: _from, amount: _amount}));
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
        bytes memory data = abi.encode(Withdraw({account: _from, amount: _amount}));
        receipt = _createTransaction(TransactionVariant.Withdraw, data);
    }

    /// @dev Creates a receipt for an action.
    function _createTransaction(TransactionVariant _transactionVariant, bytes memory _data)
        internal
        returns (uint64 onchainTx)
    {
        onchainTx = ++currentOnchainTxId;
        transactions[onchainTx] = Transaction({
            variant: _transactionVariant,
            status: TransactionStatus.Pending,
            onchainTxId: onchainTx,
            action: _data
        });

        emit TransactionPending(onchainTx, _transactionVariant, _data);
    }

    /// @dev Handles committed actions, reverts if the actions are invalid
    function _handleReceipts(StepPublicValues memory _publicValues) internal {
        // Execute the receipts.
        for (uint64 i = 0; i < _publicValues.receipts.length; i++) {
            // Increment the finalized onchain transaction ID.
            uint64 onchainTxId = ++finalizedOnchainTxId;

            // Ensure that the receipt is consistent with the transaction.
            Receipts.assertEq(transactions[onchainTxId], _publicValues.receipts[i]);

            // Ensure that the receipt is the next one to be processed.
            if (onchainTxId != _publicValues.receipts[i].onchainTxId) {
                revert ReceiptOutOfOrder();
            }

            // Ensure that the receipt has of the expected statuses.
            TransactionStatus status = _publicValues.receipts[i].status;
            if (status == TransactionStatus.None || status == TransactionStatus.Pending) {
                revert ReceiptStatusInvalid();
            }

            // Update the transaction status.
            transactions[onchainTxId].status = status;

            // If the transaction failed, emit the revert event and skip the rest of the loop.
            TransactionVariant variant = _publicValues.receipts[i].variant;
            if (status == TransactionStatus.Reverted) {
                emit TransactionReverted(onchainTxId, variant, _publicValues.receipts[i].action);
                continue;
            }

            // If the transaction completed, run a handler for the transaction.
            if (variant == TransactionVariant.Deposit) {
                // No-op.
            } else if (variant == TransactionVariant.Withdraw) {
                Withdraw memory withdraw = abi.decode(_publicValues.receipts[i].action, (Withdraw));
                _processWithdraw(withdraw.account, withdraw.amount);
            } else if (variant == TransactionVariant.CreateProver) {
                // No-op.
            } else {
                revert TransactionVariantInvalid();
            }

            // Emit the completed event.
            emit TransactionCompleted(onchainTxId, variant, _publicValues.receipts[i].action);
        }
    }

    /// @dev Processes a withdrawal by creating a claim for the amount.
    function _processWithdraw(address _account, uint256 _amount) internal {
        // Update the state.
        claimableWithdrawal[_account] += _amount;
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
