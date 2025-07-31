// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {TransactionVariant} from "../libraries/PublicValues.sol";
import {TransactionStatus} from "../libraries/PublicValues.sol";

interface ISuccinctVApp {
    /// @notice Emitted when a receipt is completed.
    event TransactionCompleted(
        uint64 indexed onchainTx, TransactionVariant indexed variant, bytes data
    );

    /// @notice Emitted when a receipt is failed.
    event TransactionReverted(
        uint64 indexed onchainTx, TransactionVariant indexed variant, bytes data
    );

    /// @notice Emitted when a receipt is pending.
    event TransactionPending(
        uint64 indexed onchainTx, TransactionVariant indexed variant, bytes data
    );

    /// @notice Emitted when a new block was committed.
    event Block(uint64 indexed block, bytes32 oldRoot, bytes32 newRoot);

    /// @notice Emitted when the program was forked.
    event Fork(uint64 indexed block, bytes32 oldVkey, bytes32 newVkey);

    /// @notice Emitted when a deposit is processed.
    event Deposit(address indexed from, uint256 amount);

    /// @notice Emitted when a withdrawal is processed.
    event Withdraw(address indexed to, uint256 amount);

    /// @notice Emitted when the auctioneer address was updated.
    event AuctioneerUpdate(address oldAuctioneer, address newAuctioneer);

    /// @notice Emitted when the staking address was updated.
    event StakingUpdate(address oldStaking, address newStaking);

    /// @notice Emitted when the verifier address was updated.
    event VerifierUpdate(address oldVerifier, address newVerifier);

    /// @notice Emitted when the minimum deposit was updated.
    event MinDepositAmountUpdate(uint256 oldMinDepositAmount, uint256 newMinDepositAmount);

    /// @dev Thrown when the caller is not the auctioneer.
    error NotAuctioneer();

    /// @dev Thrown when the caller is not the staking contract.
    error NotStaking();

    /// @dev Thrown when an address parameter is zero.
    error ZeroAddress();

    /// @dev Thrown when a hash parameter is zero.
    error ZeroHash();

    /// @dev Thrown if the actual balance does not match the expected balance.
    error BalanceMismatch();

    /// @dev Thrown when an amount parameter is invalid.
    error InvalidAmount();

    /// @dev Thrown when a root parameter is invalid.
    error InvalidRoot();

    /// @dev Thrown when an old root parameter is invalid.
    error InvalidOldRoot();

    /// @dev Thrown when a sweep transfer fails.
    error SweepTransferFailed();

    /// @dev Thrown when an invalid vkey is encountered.
    error InvalidVkey();

    /// @dev Thrown when the state is not frozen.
    error NotFrozen();

    /// @dev Thrown when an invalid proof is encountered.
    error InvalidProof();

    /// @dev Thrown when an invalid timestamp is encountered.
    error InvalidTimestamp();

    /// @dev Thrown when a timestamp is in the past.
    error TimestampInPast();

    /// @dev Thrown when a timestamp is too far in the past (more than 1 hour before the current block time).
    error TimestampTooOld();

    /// @dev Thrown when a proof fails.
    error ProofFailed();

    /// @dev Thrown when a deposit is below the minimum.
    error TransferBelowMinimum();

    /// @dev Thrown when trying to register a prover and the owner mismatches the staking contract's
    ///      owner of the prover.
    error ProverNotOwned();

    /// @dev Thrown when public values receipts are sent in an order that does not match the
    ///      onchain transaction order.
    error ReceiptOutOfOrder(uint64 expected, uint64 given);

    /// @dev Thrown when a receipt status is invalid.
    error ReceiptStatusInvalid(TransactionStatus status);

    /// @dev Thrown when a transaction variant is invalid.
    error TransactionVariantInvalid();

    /// @notice The verification key for the vApp program.
    function vkey() external view returns (bytes32);

    /// @notice The address of the $PROVE token.
    function prove() external view returns (address);

    /// @notice The address of the $iPROVE token.
    function iProve() external view returns (address);

    /// @notice The auctioneer of the VApp.
    /// @dev This is the only address that can call `step` function on the VApp.
    ///      Mutable after deployment by owner.
    function auctioneer() external view returns (address);

    /// @notice The address of the staking contract.
    function staking() external view returns (address);

    /// @notice The address of the SP1 verifier contract.
    /// @dev This can either be a specific SP1Verifier for a specific version, or the
    ///      SP1VerifierGateway which can be used to verify proofs for any version of SP1.
    ///      For the list of supported verifiers on each chain, see:
    ///      https://github.com/succinctlabs/sp1-contracts/tree/main/contracts/deployments
    function verifier() external view returns (address);

    /// @notice The block number of the last state update.
    function blockNumber() external view returns (uint64);

    /// @notice The minimum amount of $PROVE needed to deposit.
    /// @dev Since each deposit must be processed by the VApp, this prevents DoS from dust
    ///      amounts. Mutable after deployment by owner.
    function minDepositAmount() external view returns (uint256);

    /// @notice The state root for the current block.
    function root() external view returns (bytes32);

    /// @notice The timestamp for the current block.
    function timestamp() external view returns (uint64);

    /// @notice Tracks the incrementing onchainTx counter.
    function currentOnchainTxId() external view returns (uint64);

    /// @notice The onchainTx of the last finalized deposit.
    function finalizedOnchainTxId() external view returns (uint64);

    /// @notice State root for each block.
    function roots(uint64 block) external view returns (bytes32);

    /// @notice Timestamp for each block.
    function timestamps(uint64 block) external view returns (uint64);

    /// @notice Transactions for pending actions.
    function transactions(uint64 onchainTx)
        external
        view
        returns (
            TransactionVariant action,
            TransactionStatus status,
            uint64 timestamp,
            bytes memory data
        );

    /// @notice Deposit $PROVE into the prover network, must have already approved the contract as
    ///         a spender. The depositing account is credited with the $PROVE. Do not deposit with a
    ///         multisig or contract account, as funds will be unrecoverable on the prover network.
    /// @dev Because the prover network does not support contracts, only secp256k1 ECDSA EOAs can
    ///      interact with this balance. Therefor only EOAs should call this function, and funds
    ///      should only ever be transferred between EOAs on the prover network.
    /// @param amount The amount of $PROVE to deposit.
    /// @return receipt The receipt for the deposit.
    function deposit(uint256 amount) external returns (uint64 receipt);

    /// @notice Approve and deposit $PROVE in a single call using a permit signature. The depositing
    ///         account is credited with the $PROVE. Do not deposit with a multisig or contract
    ///         account, as funds will be unrecoverable on the prover network.
    /// @dev Assumes $PROVE implements permit (https://eips.ethereum.org/EIPS/eip-2612).
    ///      Because the prover network does not support contracts, only secp256k1 ECDSA EOAs can
    ///      interact with this balance. Therefor only EOAs should call this function, and funds
    ///      should only ever be transferred between EOAs on the prover network.
    /// @param from The address to spend the $PROVE from. Must correspond to the signer of the permit
    /// signature.
    /// @param amount The amount of $PROVE to spend for the deposit.
    /// @param deadline The deadline for the permit signature.
    /// @param v The v component of the permit signature.
    /// @param r The r component of the permit signature.
    /// @param s The s component of the permit signature.
    /// @return receipt The receipt for the deposit.
    function permitAndDeposit(
        address from,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint64 receipt);

    /// @notice Register a newly created prover. Only callable by the staking contract.
    /// @param prover The address of the prover.
    /// @param owner The address of the prover owner.
    /// @param stakerFeeBips The staker fee in basis points.
    function createProver(address prover, address owner, uint256 stakerFeeBips)
        external
        returns (uint64 receipt);

    /// @notice Update the state of the vApp.
    /// @dev Reverts if the committed actions are invalid.
    /// @param publicValues The public values for the state update.
    /// @param proofBytes The proof bytes for the state update.
    /// @return block The new block number.
    /// @return oldRoot The old state root.
    /// @return newRoot The new state root.
    function step(bytes calldata publicValues, bytes calldata proofBytes)
        external
        returns (uint64 block, bytes32 oldRoot, bytes32 newRoot);

    /// @notice Updates the vapp program verification key, forks the state root.
    /// @dev Only callable by the owner, executes a state update. Also increments
    ///      the block number.
    /// @param vkey The new vkey.
    /// @param root The new root.
    /// @return block The new block number.
    /// @return oldRoot The old state root.
    /// @return newRoot The new state root.
    function fork(bytes32 vkey, bytes32 root)
        external
        returns (uint64 block, bytes32 oldRoot, bytes32 newRoot);

    /// @notice Updates the auctioneer address.
    /// @dev Only callable by the owner.
    /// @param auctioneer The new auctioneer address.
    function updateAuctioneer(address auctioneer) external;

    /// @notice Updates the succinct staking contract address.
    /// @dev Only callable by the owner.
    /// @param staking The new staking contract address.
    function updateStaking(address staking) external;

    /// @notice Updates the verifier address.
    /// @dev Only callable by the owner.
    /// @param verifier The new verifier address.
    function updateVerifier(address verifier) external;

    /// @notice Updates the minimum amount for deposit operations.
    /// @dev Only callable by the owner.
    /// @param amount The new minimum amount.
    function updateMinDepositAmount(uint256 amount) external;

    /// @notice Pauses deposit, prover creation, and step.
    /// @dev Only callable by the owner.
    function pause() external;

    /// @notice Unpauses deposit, prover creation, and step.
    /// @dev Only callable by the owner.
    function unpause() external;
}
