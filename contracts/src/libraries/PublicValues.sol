// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice The type of transaction.
enum TransactionVariant {
    Deposit,
    Withdraw,
    CreateProver
}

/// @notice The status of a transaction.
enum TransactionStatus {
    None,
    Pending,
    Completed,
    Failed
}

/// @notice A transaction.
struct Transaction {
    /// @notice The variant of the transaction.
    TransactionVariant variant;
    /// @notice The status of the transaction.
    TransactionStatus status;
    /// @notice The onchain transaction ID.
    uint64 onchainTx;
    /// @notice The data of one of {DepositTransaction, WithdrawTransaction, CreateProverTransaction}.
    bytes data;
}

/// @notice The receipt for a transaction.
struct Receipt {
    /// @notice The variant of the transaction.
    TransactionVariant variant;
    /// @notice The status of the transaction.
    TransactionStatus status;
    /// @notice The onchain transaction ID.
    uint64 onchainTx;
    /// @notice The data of one of {DepositTransaction, WithdrawTransaction, CreateProverTransaction}.
    bytes data;
}

/// @notice The action data for a deposit.
struct DepositTransaction {
    address account;
    uint256 amount;
}

/// @notice The action data for a withdraw.
struct WithdrawTransaction {
    address account;
    address to;
    uint256 amount;
}

/// @notice The action data for an add signer.
struct CreateProverTransaction {
    address prover;
    address owner;
    uint256 stakerFeeBips;
}

/// @notice Internal decoded actions
struct DecodedReceipts {
    uint64 lastTxId;
    DepositTransaction[] deposits;
    WithdrawTransaction[] withdrawals;
    CreateProverTransaction[] provers;
}

/// @notice The public values encoded as a struct that can be easily deserialized inside Solidity.
struct PublicValuesStruct {
    bytes32 oldRoot;
    bytes32 newRoot;
    uint64 timestamp;
    Receipt[] receipts;
}
