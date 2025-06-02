// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    ReceiptStatus,
    Action,
    ActionType,
    DepositAction,
    WithdrawAction,
    SetDelegatedSignerAction
} from "./PublicValues.sol";

/// @notice A receipt for an action
struct Receipt {
    ActionType action;
    ReceiptStatus status;
    uint64 timestamp;
    bytes data;
}

/// @notice Internal decoded actions
struct ActionsInternal {
    uint64 lastReceipt;
    DepositInternal[] deposits;
    WithdrawInternal[] withdrawals;
    SetDelegatedSignerInternal[] setDelegatedSigners;
}

/// @notice Internal deposit action
struct DepositInternal {
    Action action;
    DepositAction data;
}

/// @notice Internal withdraw action
struct WithdrawInternal {
    Action action;
    WithdrawAction data;
}

/// @notice Internal add signer action
struct SetDelegatedSignerInternal {
    Action action;
    SetDelegatedSignerAction data;
}

/// @notice Library for handling actions
library Actions {
    /// @dev Thrown when an invalid action is encountered.
    error InvalidAction();

    /// @dev Thrown when the actions are missing.
    error MissingActions(ActionType actionType, uint64 receipt);

    /// @dev Thrown when the action does not match the receipt.
    error ActionMismatch(ActionType actionType, uint64 receipt);

    /// @dev Thrown when the receipt is invalid.
    error InvalidReceipt(ActionType actionType, uint64 expected, uint64 actual);

    /// @dev Thrown when the receipt status is invalid.
    error InvalidReceiptStatus(ActionType actionType, uint64 receipt, ReceiptStatus status);

    /// @dev Thrown when the action status is invalid.
    error InvalidActionStatus(ActionType actionType, uint64 receipt, ReceiptStatus status);

    /// @notice Memory for decoding actions.
    struct DecodeData {
        uint256 depositLength;
        uint256 withdrawLength;
        uint256 setDelegatedSignerLength;
        uint256 removeSignerLength;
    }

    /// @dev Decode actions.
    function decode(Action[] memory _actions)
        internal
        pure
        returns (ActionsInternal memory decoded)
    {
        // Build the action arrays
        DecodeData memory data;
        for (uint64 i = 0; i < _actions.length; i++) {
            ActionType actionType = _actions[i].action;
            if (actionType == ActionType.Deposit) {
                data.depositLength++;
            } else if (actionType == ActionType.Withdraw) {
                data.withdrawLength++;
            } else if (actionType == ActionType.SetDelegatedSigner) {
                data.setDelegatedSignerLength++;
            } else {
                revert InvalidAction();
            }
        }

        decoded.deposits = new DepositInternal[](data.depositLength);
        decoded.withdrawals = new WithdrawInternal[](data.withdrawLength);
        decoded.setDelegatedSigners = new SetDelegatedSignerInternal[](data.setDelegatedSignerLength);

        // Decode the actions
        data.depositLength = 0;
        data.withdrawLength = 0;
        data.setDelegatedSignerLength = 0;

        for (uint64 i = 0; i < _actions.length; i++) {
            Action memory action = _actions[i];

            if (action.receipt != 0) {
                decoded.lastReceipt = action.receipt;
            }

            if (action.action == ActionType.Deposit) {
                DepositInternal memory deposit = DepositInternal({
                    action: action,
                    data: abi.decode(action.data, (DepositAction))
                });
                decoded.deposits[data.depositLength++] = deposit;
            } else if (action.action == ActionType.Withdraw) {
                WithdrawInternal memory withdraw = WithdrawInternal({
                    action: action,
                    data: abi.decode(action.data, (WithdrawAction))
                });
                decoded.withdrawals[data.withdrawLength++] = withdraw;
            } else if (action.action == ActionType.SetDelegatedSigner) {
                SetDelegatedSignerInternal memory setDelegatedSigner = SetDelegatedSignerInternal({
                    action: action,
                    data: abi.decode(action.data, (SetDelegatedSignerAction))
                });
                decoded.setDelegatedSigners[data.setDelegatedSignerLength++] = setDelegatedSigner;
            } else {
                revert InvalidAction();
            }
        }
    }

    /// @dev Validates the actions.
    function validate(
        mapping(uint64 => Receipt) storage _receipts,
        Action[] memory _actions,
        uint64 _finalizedReceipt,
        uint64 _currentReceipt,
        uint64 _timestamp,
        uint64 _maxActionDelay
    ) internal view {
        // Ensure that the receipts exist and correspond to the matching action.
        for (uint64 i = 0; i < _actions.length; i++) {
            // Only validate actions that have a corresponding receipt.
            if (hasReceipt(_actions[i])) {
                Receipt memory receipt = _receipts[++_finalizedReceipt];

                if (_actions[i].receipt != _finalizedReceipt) {
                    revert InvalidReceipt(
                        _actions[i].action, _actions[i].receipt, _finalizedReceipt
                    );
                }

                if (receipt.status != ReceiptStatus.Pending) {
                    revert InvalidReceiptStatus(
                        _actions[i].action, _actions[i].receipt, receipt.status
                    );
                }

                if (
                    _actions[i].status != ReceiptStatus.Completed
                        && _actions[i].status != ReceiptStatus.Failed
                ) {
                    revert InvalidActionStatus(
                        _actions[i].action, _actions[i].receipt, _actions[i].status
                    );
                }

                if (_actions[i].action == ActionType.Deposit) {
                    _validateDeposit(_actions[i], receipt);
                } else if (_actions[i].action == ActionType.Withdraw) {
                    _validateWithdraw(_actions[i], receipt);
                } else if (_actions[i].action == ActionType.SetDelegatedSigner) {
                    // Skip validations
                } else {
                    revert InvalidAction();
                }
            }
        }

        // if (_finalizedReceipt < _currentReceipt) {
        //     Receipt memory receipt = _receipts[++_finalizedReceipt];
        //     if (receipt.timestamp + _maxActionDelay < _timestamp) {
        //         revert MissingActions(ActionType.Deposit, _finalizedReceipt);
        //     }
        // }
    }

    /// @dev Returns true if the action type has a corresponding receipt.
    function hasReceipt(Action memory _action) internal pure returns (bool) {
        if (_action.action == ActionType.Deposit) {
            return true;
        } else if (_action.action == ActionType.Withdraw) {
            return _action.receipt != 0;
        } else if (_action.action == ActionType.SetDelegatedSigner) {
            return true;
        }

        return false;
    }

    /// @dev Validates a deposit action, reverting if the action does not match the receipt.
    function _validateDeposit(Action memory _action, Receipt memory _receipt) internal pure {
        DepositAction memory deposit = abi.decode(_action.data, (DepositAction));
        DepositAction memory depositReceipt = abi.decode(_receipt.data, (DepositAction));

        if (deposit.account != depositReceipt.account) {
            revert ActionMismatch(ActionType.Deposit, _action.receipt);
        }
        if (deposit.amount != depositReceipt.amount) {
            revert ActionMismatch(ActionType.Deposit, _action.receipt);
        }
    }

    /// @dev Validates a withdraw action, reverting if the action does not match the receipt.
    function _validateWithdraw(Action memory _action, Receipt memory _receipt) internal pure {
        WithdrawAction memory withdraw = abi.decode(_action.data, (WithdrawAction));
        WithdrawAction memory withdrawReceipt = abi.decode(_receipt.data, (WithdrawAction));

        if (withdraw.account != withdrawReceipt.account) {
            revert ActionMismatch(ActionType.Withdraw, _action.receipt);
        }
        if (withdraw.amount != withdrawReceipt.amount) {
            revert ActionMismatch(ActionType.Withdraw, _action.receipt);
        }
        if (withdraw.to != withdrawReceipt.to) {
            revert ActionMismatch(ActionType.Withdraw, _action.receipt);
        }
    }
}
