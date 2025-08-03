// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Receipts} from "./libraries/Receipts.sol";
import {
    StepPublicValues,
    TransactionStatus,
    Receipt,
    Transaction,
    TransactionVariant,
    DepositAction,
    WithdrawAction,
    CreateProverAction
} from "./libraries/PublicValues.sol";
import {IProver} from "./interfaces/IProver.sol";
import {ISuccinctVApp} from "./interfaces/ISuccinctVApp.sol";
import {ISuccinctStaking} from "./interfaces/ISuccinctStaking.sol";
import {ISP1Verifier} from "../lib/sp1-contracts/contracts/src/ISP1Verifier.sol";
import {Initializable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
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
    bytes32 public override vkey;

    /// @inheritdoc ISuccinctVApp
    address public override prove;

    /// @inheritdoc ISuccinctVApp
    address public override iProve;

    /// @inheritdoc ISuccinctVApp
    address public override auctioneer;

    /// @inheritdoc ISuccinctVApp
    address public override staking;

    /// @inheritdoc ISuccinctVApp
    address public override verifier;

    /// @inheritdoc ISuccinctVApp
    uint64 public override blockNumber;

    /// @inheritdoc ISuccinctVApp
    uint256 public override minDepositAmount;

    /// @inheritdoc ISuccinctVApp
    uint64 public override currentOnchainTxId;

    /// @inheritdoc ISuccinctVApp
    uint64 public override finalizedOnchainTxId;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => bytes32) public override roots;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => uint64) public override timestamps;

    /// @inheritdoc ISuccinctVApp
    mapping(uint64 => Transaction) public override transactions;

    /*//////////////////////////////////////////////////////////////
                                MODIFIER
    //////////////////////////////////////////////////////////////*/

    /// @dev Modifier to ensure that the caller is the auctioneer.
    modifier onlyAuctioneer() {
        if (msg.sender != auctioneer) revert NotAuctioneer();
        _;
    }

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
        address _auctioneer,
        address _staking,
        address _verifier,
        uint256 _minDepositAmount,
        bytes32 _vkey,
        bytes32 _genesisStateRoot
    ) external initializer {
        // Ensure that parameters critical for functionality are non-zero.
        if (
            _owner == address(0) || _prove == address(0) || _iProve == address(0)
                || _auctioneer == address(0) || _staking == address(0) || _verifier == address(0)
        ) {
            revert ZeroAddress();
        }
        if (_vkey == bytes32(0) || _genesisStateRoot == bytes32(0)) {
            revert ZeroHash();
        }

        // Set the state variables.
        __UUPSUpgradeable_init();
        __Ownable_init(_owner);
        vkey = _vkey;
        prove = _prove;
        iProve = _iProve;
        _updateAuctioneer(_auctioneer);
        _updateStaking(_staking);
        _updateVerifier(_verifier);
        _updateMinDepositAmount(_minDepositAmount);

        // Set the genesis state root.
        roots[0] = _genesisStateRoot;

        // Approve the $iPROVE contract to transfer $PROVE from this contract during prover withdrawal.
        IERC20(prove).approve(_iProve, type(uint256).max);

        // Emit the events.
        emit Fork(0, bytes32(0), _vkey);
        emit Block(0, bytes32(0), _genesisStateRoot);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctVApp
    function root() external view override returns (bytes32) {
        return roots[blockNumber];
    }

    /// @inheritdoc ISuccinctVApp
    function timestamp() external view override returns (uint64) {
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
        // If the $PROVE allowance is not equal to the amount being deposited, permit this contract
        // to spend the $PROVE from the depositor.
        if (IERC20(prove).allowance(_from, address(this)) != _amount) {
            IERC20Permit(prove).permit(_from, address(this), _amount, _deadline, _v, _r, _s);
        }

        return _deposit(_from, _amount);
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
        if (_owner != IProver(_prover).owner()) {
            revert ProverNotOwned();
        }

        // Create the receipt.
        bytes memory data = abi.encode(
            CreateProverAction({prover: _prover, owner: _owner, stakerFeeBips: _stakerFeeBips})
        );
        receipt = _createTransaction(TransactionVariant.CreateProver, data);
    }

    /// @inheritdoc ISuccinctVApp
    function step(bytes calldata _publicValues, bytes calldata _proofBytes)
        external
        onlyAuctioneer
        whenNotPaused
        returns (uint64, bytes32, bytes32)
    {
        // Verify the proof.
        ISP1Verifier(verifier).verifyProof(vkey, _publicValues, _proofBytes);
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

        // Ensure the timestamp is not too far in the past (older than 1 hour).
        if (block.timestamp - publicValues.timestamp > 1 hours) {
            revert TimestampTooOld();
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
                              AUTHORIZED
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISuccinctVApp
    function fork(bytes32 _vkey, bytes32 _root)
        external
        override
        onlyOwner
        returns (uint64, bytes32, bytes32)
    {
        // Check that the new vkey and root are not zero.
        if (_vkey == bytes32(0) || _root == bytes32(0)) revert ZeroHash();

        // Save the old vkey for event.
        bytes32 oldVkey = vkey;

        // Update the vkey.
        vkey = _vkey;

        // Get the old root.
        bytes32 oldRoot = roots[blockNumber];

        // Update the root, timestamp, and produce a new block.
        uint64 newBlock = ++blockNumber;
        roots[newBlock] = _root;
        timestamps[newBlock] = uint64(block.timestamp);

        // Emit the events.
        emit Fork(newBlock, oldVkey, _vkey);
        emit Block(newBlock, oldRoot, _root);

        return (newBlock, oldRoot, _root);
    }

    /// @inheritdoc ISuccinctVApp
    function updateAuctioneer(address _auctioneer) external override onlyOwner {
        _updateAuctioneer(_auctioneer);
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
        bytes memory data = abi.encode(DepositAction({account: _from, amount: _amount}));
        receipt = _createTransaction(TransactionVariant.Deposit, data);

        // Transfer $PROVE from the sender to the VApp.
        IERC20(prove).safeTransferFrom(_from, address(this), _amount);

        emit Deposit(_from, _amount);
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
            if (_publicValues.receipts[i].onchainTxId != type(uint64).max) {
                _handleOnchainReceipt(_publicValues.receipts[i]);
            } else {
                _handleOffchainReceipt(_publicValues.receipts[i]);
            }
        }
    }

    /// @dev Handles a receipt sourced from an onchain transaction.
    function _handleOnchainReceipt(Receipt memory _receipt) internal {
        // Increment the finalized onchain transaction ID.
        uint64 onchainTxId = ++finalizedOnchainTxId;

        // Ensure that the receipt is the next one to be processed.
        if (onchainTxId != _receipt.onchainTxId) {
            revert ReceiptOutOfOrder(onchainTxId, _receipt.onchainTxId);
        }

        // Ensure that the receipt has of the expected statuses.
        if (
            _receipt.status == TransactionStatus.None
                || _receipt.status == TransactionStatus.Pending
        ) {
            revert ReceiptStatusInvalid(_receipt.status);
        }

        // Ensure that the receipt is consistent with the transaction.
        Receipts.assertEq(transactions[onchainTxId], _receipt);

        // Update the transaction status.
        transactions[onchainTxId].status = _receipt.status;

        // If the transaction failed, emit the revert event and skip the rest of the loop.
        if (_receipt.status == TransactionStatus.Reverted) {
            emit TransactionReverted(onchainTxId, _receipt.variant, _receipt.action);
            return;
        }

        // If the transaction completed, run a handler for the transaction.
        if (_receipt.variant == TransactionVariant.Deposit) {
            // No-op.
        } else if (_receipt.variant == TransactionVariant.CreateProver) {
            // No-op.
        } else {
            revert TransactionVariantInvalid();
        }

        // Emit the completed event.
        emit TransactionCompleted(onchainTxId, _receipt.variant, _receipt.action);
    }

    /// @dev Handles a receipt sourced from an offchain transaction.
    function _handleOffchainReceipt(Receipt memory _receipt) internal {
        // Ensure that the receipt has of the expected statuses.
        if (
            _receipt.status == TransactionStatus.None
                || _receipt.status == TransactionStatus.Pending
        ) {
            revert ReceiptStatusInvalid(_receipt.status);
        }

        // If the transaction reverted, don't do anything.
        if (_receipt.status == TransactionStatus.Reverted) {
            emit TransactionReverted(_receipt.onchainTxId, _receipt.variant, _receipt.action);
            return;
        }

        if (_receipt.variant == TransactionVariant.Withdraw) {
            WithdrawAction memory withdraw = abi.decode(_receipt.action, (WithdrawAction));
            _processWithdraw(withdraw.account, withdraw.amount);
        } else {
            revert TransactionVariantInvalid();
        }
    }

    /// @dev Processes a withdrawal.
    function _processWithdraw(address _to, uint256 _amount) internal {
        // If the `_to` is a prover vault, we need to first deposit it to get $iPROVE and then
        // transfer the $iPROVE to the prover vault. This splits the $PROVE amount amongst all
        // of the prover stakers.
        //
        // Otherwise if the `_to` is not a prover vault, we can just transfer the $PROVE directly.
        if (ISuccinctStaking(staking).isProver(_to)) {
            // Deposit $PROVE to mint $iPROVE, sending it to the prover vault.
            IERC4626(iProve).deposit(_amount, _to);
        } else {
            // Transfer the $PROVE from this contract to the `_to` address.
            IERC20(prove).safeTransfer(_to, _amount);
        }

        emit Withdraw(_to, _amount);
    }

    /// @dev Updates the auctioneer.
    function _updateAuctioneer(address _auctioneer) internal {
        emit AuctioneerUpdate(auctioneer, _auctioneer);

        auctioneer = _auctioneer;
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
