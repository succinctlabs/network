// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    TransactionVariant,
    TransactionStatus,
    Transaction,
    Deposit,
    Withdraw,
    CreateProver,
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
        Deposit memory deposit = abi.decode(_transaction.action, (Deposit));
        Deposit memory depositReceipt = abi.decode(_receipt.action, (Deposit));

        if (deposit.account != depositReceipt.account) {
            revert TransactionReceiptMismatch(TransactionVariant.Deposit, _receipt.onchainTxId);
        }
        if (deposit.amount != depositReceipt.amount) {
            revert TransactionReceiptMismatch(TransactionVariant.Deposit, _receipt.onchainTxId);
        }
    }

    /// @dev Asserts that the withdraw transaction matches the receipt.
    function _assertWithdrawEq(Receipt memory _receipt, Transaction memory _transaction)
        internal
        pure
    {
        Withdraw memory withdraw = abi.decode(_transaction.action, (Withdraw));
        Withdraw memory withdrawReceipt = abi.decode(_receipt.action, (Withdraw));

        if (withdraw.account != withdrawReceipt.account) {
            revert TransactionReceiptMismatch(TransactionVariant.Withdraw, _receipt.onchainTxId);
        }
        // If the requested amount to withdraw is max uint256, no validation is needed.
        if (withdraw.amount != type(uint256).max && withdraw.amount != withdrawReceipt.amount) {
            revert TransactionReceiptMismatch(TransactionVariant.Withdraw, _receipt.onchainTxId);
        }
    }

    /// @dev Asserts that the prover transaction matches the receipt.
    function _assertProverEq(Receipt memory _receipt, Transaction memory _transaction)
        internal
        pure
    {
        CreateProver memory prover = abi.decode(_transaction.action, (CreateProver));
        CreateProver memory proverReceipt = abi.decode(_receipt.action, (CreateProver));

        if (prover.prover != proverReceipt.prover) {
            revert TransactionReceiptMismatch(TransactionVariant.CreateProver, _receipt.onchainTxId);
        }
        if (prover.owner != proverReceipt.owner) {
            revert TransactionReceiptMismatch(TransactionVariant.CreateProver, _receipt.onchainTxId);
        }
        if (prover.stakerFeeBips != proverReceipt.stakerFeeBips) {
            revert TransactionReceiptMismatch(TransactionVariant.CreateProver, _receipt.onchainTxId);
        }
    }
}
