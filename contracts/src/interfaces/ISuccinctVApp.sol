// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ActionType} from "../libraries/PublicValues.sol";
import {ReceiptStatus} from "../libraries/Actions.sol";

interface ISuccinctVApp {
    /// @dev Thrown if the array lengths do not match.
    error ArrayLengthMismatch();

    /// @dev Thrown if the actual balance does not match the expected balance.
    error BalanceMismatch();

    /// @notice Updated staking.
    event UpdatedStaking(address indexed staking);

    /// @notice Updated verifier.
    event UpdatedVerifier(address indexed verifier);

    /// @notice Updated max action delay.
    event UpdatedMaxActionDelay(uint64 indexed actionDelay);

    /// @notice Updated freeze duration.
    event UpdatedFreezeDuration(uint64 indexed freezeDuration);

    /// @notice Token whitelist status changed.
    event TokenWhitelist(address indexed token, bool allowed);

    /// @notice Minimum amount updated for a token.
    event DepositBelowMinimumUpdated(address indexed token, uint256 amount);

    /// @notice Fork the program.
    event Fork(
        bytes32 indexed vkey, uint64 indexed block, bytes32 indexed newRoot, bytes32 oldRoot
    );

    /// @notice When a new block is committed.
    event Block(uint64 indexed block, bytes32 indexed newRoot, bytes32 indexed oldRoot);

    /// @notice Generalized receipt completed event for all action types.
    event ReceiptCompleted(uint64 indexed receipt, ActionType indexed action, bytes data);

    /// @notice Generalized receipt failed event for all action types.
    event ReceiptFailed(uint64 indexed receipt, ActionType indexed action, bytes data);

    /// @notice Generalized receipt pending event for all action types.
    event ReceiptPending(uint64 indexed receipt, ActionType indexed action, bytes data);

    /// @notice Withdrawal claimed event
    event WithdrawalClaimed(
        address indexed account, address indexed token, address sender, uint256 amount
    );

    /// @notice Emergency withdrawal event
    event EmergencyWithdrawal(
        address indexed account, address indexed token, uint256 balance, bytes32 root
    );

    error ZeroAddress();
    error InvalidAmount();
    error InvalidRoot();
    error InvalidOldRoot();
    error SweepTransferFailed();
    error NoWithdrawalToClaim();
    error ClaimTransferFailed();
    error InvalidVkey();
    error NotFrozen();
    error InvalidProof();
    error InvalidTimestamp();
    error TimestampInPast();
    error ProofFailed();
    error TokenNotWhitelisted();
    error TokenAlreadyWhitelisted();
    error InvalidSigner();
    error DepositBelowMinimum();

    /// @notice The maximum fee value (100% in basis points).
    function FEE_UNIT() external view returns (uint256);

    /// @notice The address of the $PROVE token.
    function prove() external view returns (address);

    /// @notice The address of the uccinct staking contract.
    function staking() external view returns (address);

    /// @notice The address of the SP1 verifier contract.
    /// @dev This can either be a specific SP1Verifier for a specific version, or the
    ///      SP1VerifierGateway which can be used to verify proofs for any version of SP1.
    ///      For the list of supported verifiers on each chain, see:
    ///      https://github.com/succinctlabs/sp1-contracts/tree/main/contracts/deployments
    function verifier() external view returns (address);

    /// @notice The verification key for the vApp program.
    function vappProgramVKey() external view returns (bytes32);

    /// @notice The block number of the last state update.
    function blockNumber() external view returns (uint64);

    /// @notice The maximum delay for actions to be committed, in seconds.
    function maxActionDelay() external view returns (uint64);

    /// @notice How long it takes for the state to be frozen.
    function freezeDuration() external view returns (uint64);

    /// @notice Mapping of whitelisted tokens.
    function whitelistedTokens(address token) external view returns (bool);

    /// @notice The minimum amount for deposit/withdraw operations for each token.
    function minAmounts(address token) external view returns (uint256);

    /// @notice The total deposits for each token on the vApp.
    function totalDeposits(address token) external view returns (uint256);

    /// @notice Tracks the incrementing receipt counter.
    function currentReceipt() external view returns (uint64);

    /// @notice The receipt of the last finalized deposit.
    function finalizedReceipt() external view returns (uint64);

    /// @notice State root for each block.
    function roots(uint64 block) external view returns (bytes32);

    /// @notice Timestamp for each block.
    function timestamps(uint64 block) external view returns (uint64);

    /// @notice Receipts for pending actions
    function receipts(uint64 receipt)
        external
        view
        returns (ActionType action, ReceiptStatus status, uint64 timestamp, bytes memory data);

    /// @notice The total pending withdrawal claims for each token
    function pendingWithdrawalClaims(address token) external view returns (uint256);

    /// @notice The signers that have been used for delegation
    function usedSigners(address signer) external view returns (bool);

    /// @notice The claimable withdrawals for each account and token
    function withdrawalClaims(address account, address token) external view returns (uint256);

    /// @notice The state root for the current block.
    function root() external view returns (bytes32);

    /// @notice The timestamp for the current block.
    function timestamp() external view returns (uint64);

    /// @notice Returns the index of a delegated signer for an owner.
    /// @param owner The owner to check.
    /// @param signer The signer to check.
    /// @return index The index of the signer, returns type(uint256).max if not found.
    function hasDelegatedSigner(address owner, address signer)
        external
        view
        returns (uint256 index);

    /// @notice The delegated signers for the owner.
    /// @param owner The owner to get the delegated signers for.
    /// @return The delegated signers.
    function getDelegatedSigners(address owner) external view returns (address[] memory);

    /// @notice Deposit funds into the vApp.
    /// @dev Scales the deposit amount by the UNIT factor
    /// @param account The account to deposit funds for.
    /// @param token The token to deposit.
    /// @param amount The amount to deposit.
    /// @return receipt The receipt for the deposit.
    function deposit(address account, address token, uint256 amount)
        external
        returns (uint64 receipt);

    /// @notice Withdraw funds from the vApp.
    /// @dev Can fail if balance is insufficient.
    /// @param to The address to withdraw funds to.
    /// @param token The token to withdraw.
    /// @param amount The amount to withdraw.
    /// @return receipt The receipt for the withdrawal.
    function withdraw(address to, address token, uint256 amount)
        external
        returns (uint64 receipt);

    /// @notice Claim a withdrawal.
    /// @dev Anyone can claim a withdrawal for an account.
    /// @param to The address to claim the withdrawal to.
    /// @param token The token to claim the withdrawal for.
    /// @return amount The amount claimed.
    function claimWithdrawal(address to, address token) external returns (uint256 amount);

    /// @notice Add a delegated signer.
    /// @dev Must be called by a prover owner.
    /// @param signer The signer to add.
    /// @return receipt The receipt for the add signer action.
    function addDelegatedSigner(address signer) external returns (uint64 receipt);

    /// @notice Remove a delegated signer.
    /// @param signer The signer to remove.
    /// @return receipt The receipt for the remove signer action.
    function removeDelegatedSigner(address signer) external returns (uint64 receipt);

    /// @notice Update the state of the vApp.
    /// @dev Reverts if the committed actions are invalid.
    /// @param publicValues The public values for the state update.
    /// @param proofBytes The proof bytes for the state update.
    /// @return The block number, the new state root, and the old state root.
    function updateState(bytes calldata publicValues, bytes calldata proofBytes)
        external
        returns (uint64, bytes32, bytes32);

    /// @notice Emergency withdrawal.
    /// @dev Anyone can call this function to withdraw their balance after the freeze duration has passed.
    /// @param token The token to withdraw.
    /// @param balance The balance to withdraw.
    /// @param proof The proof for the withdrawal.
    function emergencyWithdraw(address token, uint256 balance, bytes32[] calldata proof) external;

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

    /// @notice Updates the max action delay.
    /// @dev Only callable by the owner.
    /// @param maxActionDelay The new max action delay.
    function updateActionDelay(uint64 maxActionDelay) external;

    /// @notice Updates the freeze duration.
    /// @dev Only callable by the owner.
    /// @param freezeDuration The new freeze duration.
    function updateFreezeDuration(uint64 freezeDuration) external;

    /// @notice Adds a token to the whitelist.
    /// @dev Only callable by the owner.
    /// @param token The token to add to the whitelist.
    function addToken(address token) external;

    /// @notice Removes a token from the whitelist.
    /// @dev Only callable by the owner.
    /// @param token The token to remove from the whitelist.
    function removeToken(address token) external;

    /// @notice Updates the minimum amount for deposit/withdraw operations for each token.
    /// @dev Only callable by the owner.
    /// @param token The token to update the minimum amount for.
    /// @param amount The new minimum amount.
    function setMinimumDeposit(address token, uint256 amount) external;
}
