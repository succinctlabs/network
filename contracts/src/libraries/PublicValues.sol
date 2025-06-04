// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice The type of transaction.
enum TransactionVariant {
    Deposit,
    Withdraw,
    Prover
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
    TransactionVariant variant;
    TransactionStatus status;
    uint64 onchainTx;
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

/// @notice The receipt for a transaction.
struct Receipt {
    TransactionVariant variant;
    TransactionStatus status;
    uint64 onchainTx;
    bytes data;
}

/// @notice Internal decoded actions
struct ReceiptsInternal {
    uint64 lastTxId;
    DepositReceipt[] deposits;
    WithdrawReceipt[] withdrawals;
    CreateProverReceipt[] provers;
}

/// @notice Internal deposit action
struct DepositReceipt {
    Receipt receipt;
    DepositTransaction data;
}

/// @notice Internal withdraw action
struct WithdrawReceipt {
    Receipt receipt;
    WithdrawTransaction data;
}

/// @notice Internal add signer action
struct CreateProverReceipt {
    Receipt receipt;
    CreateProverTransaction data;
}

/// @notice The public values encoded as a struct that can be easily deserialized inside Solidity.
struct PublicValuesStruct {
    bytes32 oldRoot;
    bytes32 newRoot;
    uint64 timestamp;
    Receipt[] receipts;
}