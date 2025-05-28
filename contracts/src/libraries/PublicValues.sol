// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice The type of action to be taken.
enum ActionType {
    Deposit,
    Withdraw,
    AddSigner,
    RemoveSigner
}

/// @notice The status of a receipt
enum ReceiptStatus {
    None,
    Pending,
    Completed,
    Failed
}
/// @notice The public values encoded as a struct that can be easily deserialized inside Solidity.
struct PublicValuesStruct {
    bytes32 oldRoot;
    bytes32 newRoot;
    uint64 timestamp;
    Action[] actions;
}

/// @notice The action to be taken.
struct Action {
    ActionType action;
    ReceiptStatus status;
    uint64 receipt;
    bytes data;
}

/// @notice The action data for a deposit.
struct DepositAction {
    address account;
    address token; // TODO: Remove, only $PROVE is supported
    uint256 amount;
}

/// @notice The action data for a withdraw.
struct WithdrawAction {
    address account;
    address to;
    address token; // TODO: Remove, only $PROVE is supported
    uint256 amount;
}

/// @notice The action data for an add signer.
struct AddSignerAction {
    address owner;
    address signer;
}

/// @notice The action data for a remove signer.
struct RemoveSignerAction {
    address owner;
    address signer;
}