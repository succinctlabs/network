// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ActionType} from "../libraries/PublicValues.sol";
import {ReceiptStatus} from "../libraries/Actions.sol";

interface ISuccinctVApp {
    /// @notice Emitted when the program was forked.
    event Fork(
        bytes32 indexed vkey, uint64 indexed block, bytes32 indexed newRoot, bytes32 oldRoot
    );

    /// @notice Emitted when a new block was committed.
    event Block(uint64 indexed block, bytes32 indexed newRoot, bytes32 indexed oldRoot);

    /// @notice Emitted when a receipt is completed.
    event ReceiptCompleted(uint64 indexed receipt, ActionType indexed action, bytes data);

    /// @notice Emitted when a receipt is failed.
    event ReceiptFailed(uint64 indexed receipt, ActionType indexed action, bytes data);

    /// @notice Emitted when a receipt is pending.
    event ReceiptPending(uint64 indexed receipt, ActionType indexed action, bytes data);

    /// @notice Emitted when a withdrawal is claimed.
    event Withdrawal(address indexed account, uint256 amount);

    /// @notice Emitted when the staking address was updated.
    event StakingUpdate(address oldStaking, address newStaking);

    /// @notice Emitted when the verifier address was updated.
    event VerifierUpdate(address oldVerifier, address newVerifier);

    /// @notice Emitted when the fee vault was updated.
    event FeeVaultUpdate(address oldFeeVault, address newFeeVault);

    /// @notice Emitted when the max action delay was updated.
    event MaxActionDelayUpdate(uint64 oldMaxActionDelay, uint64 newMaxActionDelay);

    /// @notice Emitted when the minimum deposit was updated.
    event MinDepositAmountUpdate(uint256 oldMinDepositAmount, uint256 newMinDepositAmount);

    /// @notice Emitted when the protocol fee was updated.
    event ProtocolFeeBipsUpdate(uint256 oldProtocolFeeBips, uint256 newProtocolFeeBips);

    /// @dev Thrown when the caller is not the staking contract.
    error NotStaking();

    /// @dev Thrown when an address parameter is zero.
    error ZeroAddress();
    
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

    /// @dev Thrown when there is no withdrawal to claim.
    error NoWithdrawalToClaim();

    /// @dev Thrown when a claim transfer fails.
    error ClaimTransferFailed();

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

    /// @dev Thrown when a proof fails.
    error ProofFailed();

    /// @dev Thrown when a deposit or withdrawal is below the minimum.
    error TransferBelowMinimum();

    /// @dev Thrown when trying to add a signer that is already a delegate of another prover.
    error SignerAlreadyUsed();

    /// @dev Thrown when trying to add a signer for an owner that is not a prover.
    error OwnerNotProver();

    /// @dev Thrown when trying to add a signer for a prover that is a prover.
    error SignerIsProver();

    /// @notice The address of the $PROVE token.
    function prove() external view returns (address);

    /// @notice The address of the $iPROVE token.
    function iProve() external view returns (address);

    /// @notice The address of the Succinct staking contract.
    function staking() external view returns (address);

    /// @notice The address of the SP1 verifier contract.
    /// @dev This can either be a specific SP1Verifier for a specific version, or the
    ///      SP1VerifierGateway which can be used to verify proofs for any version of SP1.
    ///      For the list of supported verifiers on each chain, see:
    ///      https://github.com/succinctlabs/sp1-contracts/tree/main/contracts/deployments
    function verifier() external view returns (address);

    /// @notice The address of the fee vault, where protocol fees are sent.
    function feeVault() external view returns (address);

    /// @notice The verification key for the vApp program.
    function vappProgramVKey() external view returns (bytes32);

    /// @notice The block number of the last state update.
    function blockNumber() external view returns (uint64);

    /// @notice The maximum delay for actions to be committed, in seconds.
    function maxActionDelay() external view returns (uint64);

    /// @notice The minimum amount for deposit/withdraw operations.
    function minDepositAmount() external view returns (uint256);

    /// @notice The protocol fee in basis points.
    function protocolFeeBips() external view returns (uint256);

    /// @notice The state root for the current block.
    function root() external view returns (bytes32);

    /// @notice The timestamp for the current block.
    function timestamp() external view returns (uint64);

    /// @notice Tracks the incrementing receipt counter.
    function currentReceipt() external view returns (uint64);

    /// @notice The receipt of the last finalized deposit.
    function finalizedReceipt() external view returns (uint64);

    /// @notice State root for each block.
    function roots(uint64 block) external view returns (bytes32);

    /// @notice Timestamp for each block.
    function timestamps(uint64 block) external view returns (uint64);

    /// @notice The claimable withdrawal amount for each account.
    function claimableWithdrawal(address account) external view returns (uint256);

    /// @notice Receipts for pending actions
    function receipts(uint64 receipt)
        external
        view
        returns (ActionType action, ReceiptStatus status, uint64 timestamp, bytes memory data);

    /// @notice The signers that have been used for delegation.
    function usedSigners(address signer) external view returns (bool);

    /// @notice The delegated signer for an owner.
    function delegatedSigner(address owner) external view returns (address);

    /// @notice Deposit funds into the vApp, must have already approved the contract as a spender.
    /// @param amount The amount of $PROVE to deposit.
    /// @return receipt The receipt for the deposit.
    function deposit(uint256 amount) external returns (uint64 receipt);

    /// @notice Approve and deposit $PROVE in a single call using a permit signature.
    /// @dev Assumes $PROVE implements permit (https://eips.ethereum.org/EIPS/eip-2612).
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

    /// @notice Request to withdraw funds from the contract.
    /// @dev This request can also be done offchain.
    /// @param to The address to withdraw funds to.
    /// @param amount The amount to withdraw. MUST be less than or equal to the balance, except
    ///        in the case of type(uint256).max, in which case the entire balance is withdrawn.
    /// @return receipt The receipt for the withdrawal.
    function requestWithdraw(address to, uint256 amount) external returns (uint64 receipt);

    /// @notice Claim a pending withdrawal from the contract.
    /// @param to The address to claim the withdrawal to.
    /// @return amount The amount claimed.
    function finishWithdrawal(address to) external returns (uint256 amount);

    /// @notice Set a delegated signer for a prover owner. This allows the owner EOA to sign messages
    ///         on behalf of the prover. Only one signer can be a delegate for a prover at a time.
    /// @dev Must be called by the staking contract.
    /// @param owner The owner to add the signer for.
    /// @param signer The signer to add.
    /// @return receipt The receipt for the set delegated signer action.
    function setDelegatedSigner(address owner, address signer) external returns (uint64 receipt);

    /// @notice Update the state of the vApp.
    /// @dev Reverts if the committed actions are invalid.
    /// @param publicValues The public values for the state update.
    /// @param proofBytes The proof bytes for the state update.
    /// @return The block number, the new state root, and the old state root.
    function updateState(bytes calldata publicValues, bytes calldata proofBytes)
        external
        returns (uint64, bytes32, bytes32);

    /// @notice Updates the vapp program verification key, forks the state root.
    /// @dev Only callable by the owner, executes a state update.
    /// @param vkey The new vkey.
    /// @param newOldRoot The old root committed by the new program.
    /// @param publicValues The encoded public values.
    /// @param proofBytes The encoded proof.
    /// @return The block number, the new state root, and the old state root.
    function fork(
        bytes32 vkey,
        bytes32 newOldRoot,
        bytes calldata publicValues,
        bytes calldata proofBytes
    ) external returns (uint64, bytes32, bytes32);

    /// @notice Updates the succinct staking contract address.
    /// @dev Only callable by the owner.
    /// @param staking The new staking contract address.
    function updateStaking(address staking) external;

    /// @notice Updates the verifier address.
    /// @dev Only callable by the owner.
    /// @param verifier The new verifier address.
    function updateVerifier(address verifier) external;

    /// @notice Updates the fee vault address.
    /// @dev Only callable by the owner.
    /// @param feeVault The new fee vault address.
    function updateFeeVault(address feeVault) external;

    /// @notice Updates the max action delay.
    /// @dev Only callable by the owner.
    /// @param delay The new max action delay.
    function updateActionDelay(uint64 delay) external;

    /// @notice Updates the minimum amount for deposit/withdraw operations.
    /// @dev Only callable by the owner.
    /// @param amount The new minimum amount.
    function updateMinDepositAmount(uint256 amount) external;

    /// @notice Updates the protocol fee in basis points.
    /// @dev Only callable by the owner.
    /// @param protocolFeeBips The new protocol fee in basis points.
    function updateProtocolFeeBips(uint256 protocolFeeBips) external;
}
