// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    TransactionVariant,
    Transaction,
    DepositAction,
    CreateProverAction,
    Receipt
} from "./PublicValues.sol";

/// @notice Library for handling receipts
library Receipts {
    /// @dev Thrown when an unsupported transaction is encountered.
    error UnsupportedTransactionVariant();

    /// @dev Thrown when the transaction variant does not match the receipt variant.
    error TransactionVariantMismatch(TransactionVariant variant, TransactionVariant receipt);

    /// @dev Thrown when the transaction does not match the receipt.
    error TransactionReceiptMismatch(TransactionVariant variant, uint64 receipt);

    /// @dev Asserts that the transaction and receipt are consistent.
    function assertEq(Transaction memory _transaction, Receipt memory _receipt) internal pure {
        if (_receipt.variant == TransactionVariant.Deposit) {
            _assertDepositEq(_receipt, _transaction);
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
        if (_receipt.variant != TransactionVariant.Deposit) {
            revert TransactionVariantMismatch(_transaction.variant, _receipt.variant);
        } else if (_transaction.variant != TransactionVariant.Deposit) {
            revert TransactionVariantMismatch(_transaction.variant, _receipt.variant);
        }

        DepositAction memory deposit = abi.decode(_transaction.action, (DepositAction));
        DepositAction memory depositReceipt = abi.decode(_receipt.action, (DepositAction));

        if (deposit.account != depositReceipt.account) {
            revert TransactionReceiptMismatch(TransactionVariant.Deposit, _receipt.onchainTxId);
        }
        if (deposit.amount != depositReceipt.amount) {
            revert TransactionReceiptMismatch(TransactionVariant.Deposit, _receipt.onchainTxId);
        }
    }

    /// @dev Asserts that the prover transaction matches the receipt.
    function _assertProverEq(Receipt memory _receipt, Transaction memory _transaction)
        internal
        pure
    {
        if (_receipt.variant != TransactionVariant.CreateProver) {
            revert TransactionVariantMismatch(_transaction.variant, _receipt.variant);
        } else if (_transaction.variant != TransactionVariant.CreateProver) {
            revert TransactionVariantMismatch(_transaction.variant, _receipt.variant);
        }

        CreateProverAction memory prover = abi.decode(_transaction.action, (CreateProverAction));
        CreateProverAction memory proverReceipt = abi.decode(_receipt.action, (CreateProverAction));

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
