// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice A transaction.
struct Transaction {
    /// @notice The variant of the transaction.
    TransactionVariant variant;
    /// @notice The status of the transaction.
    TransactionStatus status;
    /// @notice The onchain transaction ID.
    uint64 onchainTxId;
    /// @notice The action of one of {Deposit, Withdraw, CreateProver}.
    bytes action;
}

/// @notice The receipt for a transaction.
struct Receipt {
    /// @notice The variant of the transaction.
    TransactionVariant variant;
    /// @notice The status of the transaction.
    TransactionStatus status;
    /// @notice The onchain transaction ID.
    uint64 onchainTxId;
    /// @notice The action of one of {Deposit, Withdraw, CreateProver}.
    bytes action;
}

/// @notice The type of transaction.
enum TransactionVariant {
    Deposit,
    Withdraw,
    CreateProver
}

/// @notice The status of a transaction.
enum TransactionStatus {
    /// The transaction has no initialiezd status.
    None,
    /// The transaction has been included in the ledger but is not yet executed.
    Pending,
    /// The transaction executed successfully.
    Completed,
    /// The transaction reverted during execution.
    Reverted
}

/// @notice The action data for a deposit.
struct DepositAction {
    address account;
    uint256 amount;
}

/// @notice The action data for a withdraw.
struct WithdrawAction {
    address account;
    uint256 amount;
}

/// @notice The action data for an add signer.
struct CreateProverAction {
    address prover;
    address owner;
    uint256 stakerFeeBips;
}

/// @notice The public values encoded as a struct that can be easily deserialized inside Solidity.
struct StepPublicValues {
    bytes32 oldRoot;
    bytes32 newRoot;
    uint64 timestamp;
    Receipt[] receipts;
}
