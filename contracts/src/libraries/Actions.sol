// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    ReceiptStatus,
    Action,
    ActionType,
    DepositAction,
    WithdrawAction,
    AddSignerAction,
    RemoveSignerAction,
    SlashAction,
    RewardAction,
    ProverStateAction,
    FeeUpdateAction
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
    DepositInternal[] deposits;
    WithdrawInternal[] withdrawals;
    AddSignerInternal[] addSigners;
    RemoveSignerInternal[] removeSigners;
    SlashInternal[] slashes;
    RewardInternal[] rewards;
    ProverStateInternal[] proverStates;
    FeeUpdateInternal[] feeUpdates;
    uint64 lastReceipt;
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
struct AddSignerInternal {
    Action action;
    AddSignerAction data;
}

/// @notice Internal remove signer action
struct RemoveSignerInternal {
    Action action;
    RemoveSignerAction data;
}

/// @notice Internal slash action
struct SlashInternal {
    Action action;
    SlashAction data;
}

/// @notice Internal reward action
struct RewardInternal {
    Action action;
    RewardAction data;
}

/// @notice Internal prover state action
struct ProverStateInternal {
    Action action;
    ProverStateAction data;
}

/// @notice Internal fee update action
struct FeeUpdateInternal {
    Action action;
    FeeUpdateAction data;
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

    /// @notice Memory for decoding actions
    struct DecodeData {
        uint256 depositLength;
        uint256 withdrawLength;
        uint256 addSignerLength;
        uint256 removeSignerLength;
        uint256 slashLength;
        uint256 rewardLength;
        uint256 proverStateLength;
        uint256 feeUpdateLength;
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
            } else if (actionType == ActionType.AddSigner) {
                data.addSignerLength++;
            } else if (actionType == ActionType.RemoveSigner) {
                data.removeSignerLength++;
            } else if (actionType == ActionType.Slash) {
                data.slashLength++;
            } else if (actionType == ActionType.Reward) {
                data.rewardLength++;
            } else if (actionType == ActionType.ProverState) {
                data.proverStateLength++;
            } else if (actionType == ActionType.FeeUpdate) {
                data.feeUpdateLength++;
            } else {
                revert InvalidAction();
            }
        }

        decoded.deposits = new DepositInternal[](data.depositLength);
        decoded.withdrawals = new WithdrawInternal[](data.withdrawLength);
        decoded.addSigners = new AddSignerInternal[](data.addSignerLength);
        decoded.removeSigners = new RemoveSignerInternal[](data.removeSignerLength);
        decoded.slashes = new SlashInternal[](data.slashLength);
        decoded.rewards = new RewardInternal[](data.rewardLength);
        decoded.proverStates = new ProverStateInternal[](data.proverStateLength);
        decoded.feeUpdates = new FeeUpdateInternal[](data.feeUpdateLength);

        // Decode the actions
        data.depositLength = 0;
        data.withdrawLength = 0;
        data.addSignerLength = 0;
        data.removeSignerLength = 0;
        data.slashLength = 0;
        data.rewardLength = 0;
        data.proverStateLength = 0;
        data.feeUpdateLength = 0;
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
            } else if (action.action == ActionType.AddSigner) {
                AddSignerInternal memory addSigner = AddSignerInternal({
                    action: action,
                    data: abi.decode(action.data, (AddSignerAction))
                });
                decoded.addSigners[data.addSignerLength++] = addSigner;
            } else if (action.action == ActionType.RemoveSigner) {
                RemoveSignerInternal memory removeSigner = RemoveSignerInternal({
                    action: action,
                    data: abi.decode(action.data, (RemoveSignerAction))
                });
                decoded.removeSigners[data.removeSignerLength++] = removeSigner;
            } else if (action.action == ActionType.Slash) {
                SlashInternal memory slash =
                    SlashInternal({action: action, data: abi.decode(action.data, (SlashAction))});
                decoded.slashes[data.slashLength++] = slash;
            } else if (action.action == ActionType.Reward) {
                RewardInternal memory reward =
                    RewardInternal({action: action, data: abi.decode(action.data, (RewardAction))});
                decoded.rewards[data.rewardLength++] = reward;
            } else if (action.action == ActionType.ProverState) {
                ProverStateInternal memory proverState = ProverStateInternal({
                    action: action,
                    data: abi.decode(action.data, (ProverStateAction))
                });
                decoded.proverStates[data.proverStateLength++] = proverState;
            } else if (action.action == ActionType.FeeUpdate) {
                FeeUpdateInternal memory feeUpdate = FeeUpdateInternal({
                    action: action,
                    data: abi.decode(action.data, (FeeUpdateAction))
                });
                decoded.feeUpdates[data.feeUpdateLength++] = feeUpdate;
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
        // Ensure that the receipts exist and correspond to the matching action
        for (uint64 i = 0; i < _actions.length; i++) {
            // Only validate actions that have a corresponding receipt
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
                    _deposit(_actions[i], receipt);
                } else if (_actions[i].action == ActionType.Withdraw) {
                    _withdraw(_actions[i], receipt);
                } else if (_actions[i].action == ActionType.AddSigner) {
                    // Skip validations
                } else if (_actions[i].action == ActionType.RemoveSigner) {
                    // Skip validations
                } else if (_actions[i].action == ActionType.Slash) {
                    // Skip validations
                } else if (_actions[i].action == ActionType.Reward) {
                    // Skip validations
                } else if (_actions[i].action == ActionType.ProverState) {
                    // Skip validations
                } else if (_actions[i].action == ActionType.FeeUpdate) {
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
        } else if (_action.action == ActionType.AddSigner) {
            return true;
        } else if (_action.action == ActionType.RemoveSigner) {
            return true;
        } else if (_action.action == ActionType.Slash) {
            return false;
        } else if (_action.action == ActionType.Reward) {
            return false;
        } else if (_action.action == ActionType.ProverState) {
            return false;
        } else if (_action.action == ActionType.FeeUpdate) {
            return false;
        }

        return false;
    }

    /// @dev Validates a deposit action, reverting if the action does not match the receipt.
    function _deposit(Action memory _action, Receipt memory _receipt) internal pure {
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
    function _withdraw(Action memory _action, Receipt memory _receipt) internal pure {
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
