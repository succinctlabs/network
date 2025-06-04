// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    TransactionVariant,
    TransactionStatus,
    DecodedReceipts,
    DepositTransaction,
    WithdrawTransaction,
    CreateProverTransaction,
    Transaction,
    Receipt
} from "./PublicValues.sol";

/// @notice Library for handling receipts
library Receipts {
    /// @dev Thrown when an unsupported transaction is encountered.
    error UnsupportedTransactionVariant();

    /// @dev Thrown when the transaction does not match the receipt.
    error TransactionReceiptMismatch(TransactionVariant variant, uint64 receipt);

    /// @dev Asserts that the transaction and receipt are consistent.
    function assertEq(Transaction memory _transaction, Receipt memory _receipt) internal pure {
        if (_receipt.variant == TransactionVariant.Deposit) {
            _assertDepositEq(_receipt, _transaction);
        } else if (_receipt.variant == TransactionVariant.Withdraw) {
            _assertWithdrawEq(_receipt, _transaction);
        } else if (_receipt.variant == TransactionVariant.CreateProver) {
            _assertProverEq(_receipt, _transaction);
        } else {
            revert UnsupportedTransactionVariant();
        }
    }

    /// @dev Asserts that the deposit transaction matches the receipt.
    function _assertDepositEq(Receipt memory _receipt, Transaction memory _transaction)
        internal
        pure
    {
        DepositTransaction memory deposit = abi.decode(_transaction.data, (DepositTransaction));
        DepositTransaction memory depositReceipt = abi.decode(_receipt.data, (DepositTransaction));

        if (deposit.account != depositReceipt.account) {
            revert TransactionReceiptMismatch(TransactionVariant.Deposit, _receipt.onchainTx);
        }
        if (deposit.amount != depositReceipt.amount) {
            revert TransactionReceiptMismatch(TransactionVariant.Deposit, _receipt.onchainTx);
        }
    }

    /// @dev Asserts that the withdraw transaction matches the receipt.
    function _assertWithdrawEq(Receipt memory _receipt, Transaction memory _transaction)
        internal
        pure
    {
        WithdrawTransaction memory withdraw = abi.decode(_transaction.data, (WithdrawTransaction));
        WithdrawTransaction memory withdrawReceipt =
            abi.decode(_receipt.data, (WithdrawTransaction));

        if (withdraw.account != withdrawReceipt.account) {
            revert TransactionReceiptMismatch(TransactionVariant.Withdraw, _receipt.onchainTx);
        }
        if (withdraw.amount != withdrawReceipt.amount) {
            revert TransactionReceiptMismatch(TransactionVariant.Withdraw, _receipt.onchainTx);
        }
        if (withdraw.to != withdrawReceipt.to) {
            revert TransactionReceiptMismatch(TransactionVariant.Withdraw, _receipt.onchainTx);
        }
    }

    /// @dev Asserts that the prover transaction matches the receipt.
    function _assertProverEq(Receipt memory _receipt, Transaction memory _transaction)
        internal
        pure
    {
        CreateProverTransaction memory prover =
            abi.decode(_transaction.data, (CreateProverTransaction));
        CreateProverTransaction memory proverReceipt =
            abi.decode(_receipt.data, (CreateProverTransaction));

        if (prover.prover != proverReceipt.prover) {
            revert TransactionReceiptMismatch(TransactionVariant.CreateProver, _receipt.onchainTx);
        }
        if (prover.owner != proverReceipt.owner) {
            revert TransactionReceiptMismatch(TransactionVariant.CreateProver, _receipt.onchainTx);
        }
        if (prover.stakerFeeBips != proverReceipt.stakerFeeBips) {
            revert TransactionReceiptMismatch(TransactionVariant.CreateProver, _receipt.onchainTx);
        }
    }
}
