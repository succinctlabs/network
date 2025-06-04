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
    /// @dev Thrown when an invalid action is encountered.
    error InvalidTransactionVariant();

    /// @dev Thrown when the receipts are missing.
    error MissingReceipts(TransactionVariant variant, uint64 receipt);

    /// @dev Thrown when the action does not match the receipt.
    error ReceiptMismatch(TransactionVariant variant, uint64 receipt);

    /// @dev Thrown when the receipt is invalid.
    error InvalidReceipt(TransactionVariant variant, uint64 expected, uint64 actual);

    /// @dev Thrown when the receipt status is invalid.
    error InvalidReceiptStatus(TransactionVariant variant, uint64 receipt, TransactionStatus status);

    /// @dev Validates the actions.
    function validate(
        mapping(uint64 => Transaction) storage _transactions,
        Receipt[] memory _receipts,
        uint64 _finalizedReceipt
    ) internal view {
        for (uint64 i = 0; i < _receipts.length; i++) {
            if (_hasReceipt(_receipts[i])) {
                // Fetch the next transaction that should be finalized.
                Transaction memory transaction = _transactions[++_finalizedReceipt];

                // Validate that the receipt is the next one to be processed.
                if (_receipts[i].onchainTx != _finalizedReceipt) {
                    revert InvalidReceipt(
                        _receipts[i].variant, _receipts[i].onchainTx, _finalizedReceipt
                    );
                }

                // Validate the receipt based on the transaction variant.
                if (_receipts[i].variant == TransactionVariant.Deposit) {
                    _validateDeposit(_receipts[i], transaction);
                } else if (_receipts[i].variant == TransactionVariant.Withdraw) {
                    _validateWithdraw(_receipts[i], transaction);
                } else if (_receipts[i].variant == TransactionVariant.CreateProver) {
                    _validateProver(_receipts[i], transaction);
                } else {
                    revert InvalidTransactionVariant();
                }
            }
        }
    }

    /// @dev Returns true if the action type has a corresponding receipt.
    function _hasReceipt(Receipt memory _action) internal pure returns (bool) {
        if (_action.variant == TransactionVariant.Deposit) {
            return true;
        } else if (_action.variant == TransactionVariant.Withdraw) {
            return true;
        } else if (_action.variant == TransactionVariant.CreateProver) {
            return true;
        }

        return false;
    }

    /// @dev Validates a deposit action, reverting if the action does not match the receipt.
    function _validateDeposit(Receipt memory _receipt, Transaction memory _transaction)
        internal
        pure
    {
        DepositTransaction memory deposit = abi.decode(_transaction.data, (DepositTransaction));
        DepositTransaction memory depositReceipt = abi.decode(_receipt.data, (DepositTransaction));

        if (deposit.account != depositReceipt.account) {
            revert ReceiptMismatch(TransactionVariant.Deposit, _receipt.onchainTx);
        }
        if (deposit.amount != depositReceipt.amount) {
            revert ReceiptMismatch(TransactionVariant.Deposit, _receipt.onchainTx);
        }
    }

    /// @dev Validates a withdraw action, reverting if the action does not match the receipt.
    function _validateWithdraw(Receipt memory _receipt, Transaction memory _transaction)
        internal
        pure
    {
        WithdrawTransaction memory withdraw = abi.decode(_transaction.data, (WithdrawTransaction));
        WithdrawTransaction memory withdrawReceipt =
            abi.decode(_receipt.data, (WithdrawTransaction));

        if (withdraw.account != withdrawReceipt.account) {
            revert ReceiptMismatch(TransactionVariant.Withdraw, _receipt.onchainTx);
        }
        if (withdraw.amount != withdrawReceipt.amount) {
            revert ReceiptMismatch(TransactionVariant.Withdraw, _receipt.onchainTx);
        }
        if (withdraw.to != withdrawReceipt.to) {
            revert ReceiptMismatch(TransactionVariant.Withdraw, _receipt.onchainTx);
        }
    }

    /// @dev Validates a prover action, reverting if the action does not match the receipt.
    function _validateProver(Receipt memory _receipt, Transaction memory _transaction)
        internal
        pure
    {
        CreateProverTransaction memory prover =
            abi.decode(_transaction.data, (CreateProverTransaction));
        CreateProverTransaction memory proverReceipt =
            abi.decode(_receipt.data, (CreateProverTransaction));

        if (prover.prover != proverReceipt.prover) {
            revert ReceiptMismatch(TransactionVariant.CreateProver, _receipt.onchainTx);
        }
        if (prover.owner != proverReceipt.owner) {
            revert ReceiptMismatch(TransactionVariant.CreateProver, _receipt.onchainTx);
        }
        if (prover.stakerFeeBips != proverReceipt.stakerFeeBips) {
            revert ReceiptMismatch(TransactionVariant.CreateProver, _receipt.onchainTx);
        }
    }
}
