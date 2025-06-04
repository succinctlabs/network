// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    TransactionVariant,
    TransactionStatus,
    Receipt,
    ReceiptsInternal,
    DepositReceipt,
    WithdrawReceipt,
    CreateProverReceipt,
    DepositTransaction,
    WithdrawTransaction,
    CreateProverTransaction,
    Transaction
} from "./PublicValues.sol";

/// @notice Library for handling actions
library Actions {
    /// @dev Thrown when an invalid action is encountered.
    error InvalidAction();

    /// @dev Thrown when the actions are missing.
    error MissingActions(TransactionVariant actionType, uint64 receipt);

    /// @dev Thrown when the action does not match the receipt.
    error ActionMismatch(TransactionVariant actionType, uint64 receipt);

    /// @dev Thrown when the receipt is invalid.
    error InvalidReceipt(TransactionVariant actionType, uint64 expected, uint64 actual);

    /// @dev Thrown when the receipt status is invalid.
    error InvalidReceiptStatus(TransactionVariant actionType, uint64 receipt, TransactionStatus status);

    /// @dev Thrown when the action status is invalid.
    error InvalidActionStatus(TransactionVariant actionType, uint64 receipt, TransactionStatus status);

    /// @notice Memory for decoding actions.
    struct DecodeData {
        uint256 depositLength;
        uint256 withdrawLength;
        uint256 setDelegatedSignerLength;
        uint256 removeSignerLength;
    }

    /// @dev Decode actions.
    function decode(Receipt[] memory _actions)
        internal
        pure
        returns (ReceiptsInternal memory decoded)
    {
        // Build the action arrays
        DecodeData memory data;
        for (uint64 i = 0; i < _actions.length; i++) {
            TransactionVariant actionType = _actions[i].variant;
            if (actionType == TransactionVariant.Deposit) {
                data.depositLength++;
            } else if (actionType == TransactionVariant.Withdraw) {
                data.withdrawLength++;
            } else if (actionType == TransactionVariant.Prover) {
                data.setDelegatedSignerLength++;
            } else {
                revert InvalidAction();
            }
        }

        decoded.deposits = new DepositReceipt[](data.depositLength);
        decoded.withdrawals = new WithdrawReceipt[](data.withdrawLength);
        decoded.provers = new CreateProverReceipt[](data.setDelegatedSignerLength);

        // Decode the actions
        data.depositLength = 0;
        data.withdrawLength = 0;
        data.setDelegatedSignerLength = 0;

        for (uint64 i = 0; i < _actions.length; i++) {
            Receipt memory action = _actions[i];

            decoded.lastTxId = action.onchainTx;

            if (action.variant == TransactionVariant.Deposit) {
                DepositReceipt memory deposit = DepositReceipt({
                    receipt: action,
                    data: abi.decode(action.data, (DepositTransaction))
                });
                decoded.deposits[data.depositLength++] = deposit;
            } else if (action.variant == TransactionVariant.Withdraw) {
                WithdrawReceipt memory withdraw = WithdrawReceipt({
                    receipt: action,
                    data: abi.decode(action.data, (WithdrawTransaction))
                });
                decoded.withdrawals[data.withdrawLength++] = withdraw;
            } else if (action.variant == TransactionVariant.Prover) {
                CreateProverReceipt memory setDelegatedSigner = CreateProverReceipt({
                    receipt: action,
                    data: abi.decode(action.data, (CreateProverTransaction))
                });
                decoded.provers[data.setDelegatedSignerLength++] = setDelegatedSigner;
            } else {
                revert InvalidAction();
            }
        }
    }

    /// @dev Validates the actions.
    function validate(
        mapping(uint64 => Transaction) storage _transactions,
        Receipt[] memory _actions,
        uint64 _finalizedReceipt,
        uint64 _currentReceipt,
        uint64 _timestamp
    ) internal view {
        // Ensure that the receipts exist and correspond to the matching action.
        for (uint64 i = 0; i < _actions.length; i++) {
            // Only validate actions that have a corresponding receipt.
            if (hasReceipt(_actions[i])) {
                Transaction memory transaction = _transactions[++_finalizedReceipt];

                if (_actions[i].onchainTx != _finalizedReceipt) {
                    revert InvalidReceipt(
                        _actions[i].variant, _actions[i].onchainTx, _finalizedReceipt
                    );
                }

                if (transaction.status != TransactionStatus.Pending) {
                    revert InvalidReceiptStatus(
                        _actions[i].variant, _actions[i].onchainTx, transaction.status
                    );
                }

                if (
                    _actions[i].status != TransactionStatus.Completed
                        && _actions[i].status != TransactionStatus.Failed
                ) {
                    revert InvalidActionStatus(
                        _actions[i].variant, _actions[i].onchainTx, transaction.status
                    );
                }

                if (_actions[i].variant == TransactionVariant.Deposit) {
                    // _validateDeposit(_actions[i], receipt);
                } else if (_actions[i].variant == TransactionVariant.Withdraw) {
                    // _validateWithdraw(_actions[i], receipt);
                } else if (_actions[i].variant == TransactionVariant.Prover) {
                    // Skip validations
                } else {
                    revert InvalidAction();
                }
            }
        }

        // if (_finalizedReceipt < _currentReceipt) {
        //     Receipt memory receipt = _receipts[++_finalizedReceipt];
        //     if (receipt.timestamp + _maxActionDelay < _timestamp) {
        //         revert MissingActions(TransactionVariant.Deposit, _finalizedReceipt);
        //     }
        // }
    }

    /// @dev Returns true if the action type has a corresponding receipt.
    function hasReceipt(Receipt memory _action) internal pure returns (bool) {
        if (_action.variant == TransactionVariant.Deposit) {
            return true;
        } else if (_action.variant == TransactionVariant.Withdraw) {
            return true;
        } else if (_action.variant == TransactionVariant.Prover) {
            return true;
        }

        return false;
    }

    // /// @dev Validates a deposit action, reverting if the action does not match the receipt.
    // function _validateDeposit(Action memory _action, Receipt memory _receipt) internal pure {
    //     DepositAction memory deposit = abi.decode(_action.data, (DepositAction));
    //     DepositAction memory depositReceipt = abi.decode(_receipt.data, (DepositAction));

    //     if (deposit.account != depositReceipt.account) {
    //         revert ActionMismatch(ActionType.Deposit, _action.receipt);
    //     }
    //     if (deposit.amount != depositReceipt.amount) {
    //         revert ActionMismatch(ActionType.Deposit, _action.receipt);
    //     }
    // }

    // /// @dev Validates a withdraw action, reverting if the action does not match the receipt.
    // function _validateWithdraw(Action memory _action, Receipt memory _receipt) internal pure {
    //     WithdrawAction memory withdraw = abi.decode(_action.data, (WithdrawAction));
    //     WithdrawAction memory withdrawReceipt = abi.decode(_receipt.data, (WithdrawAction));

    //     if (withdraw.account != withdrawReceipt.account) {
    //         revert ActionMismatch(ActionType.Withdraw, _action.receipt);
    //     }
    //     if (withdraw.amount != withdrawReceipt.amount) {
    //         revert ActionMismatch(ActionType.Withdraw, _action.receipt);
    //     }
    //     if (withdraw.to != withdrawReceipt.to) {
    //         revert ActionMismatch(ActionType.Withdraw, _action.receipt);
    //     }
    // }
}
