// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Receipts} from "../src/libraries/Receipts.sol";
import {
    StepPublicValues,
    TransactionStatus,
    Receipt as TxReceipt,
    TransactionVariant,
    Deposit,
    Withdraw,
    CreateProver
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract SuccinctVAppWithdrawTest is SuccinctVAppTest {
    function test_Withdraw_WhenValid() public {
        uint256 amount = SuccinctVApp(VAPP).minDepositAmount();

        // Deposit
        MockERC20(PROVE).mint(REQUESTER_1, amount);
        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(VAPP, amount);
        uint64 depositReceipt = SuccinctVApp(VAPP).deposit(amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData = abi.encode(Deposit({account: REQUESTER_1, amount: amount}));
        StepPublicValues memory depositPublicValues = StepPublicValues({
            receipts: new TxReceipt[](1),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        depositPublicValues.receipts[0] = TxReceipt({
            variant: TransactionVariant.Deposit,
            status: TransactionStatus.Completed,
            onchainTxId: depositReceipt,
            action: depositData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionCompleted(
            depositReceipt, TransactionVariant.Deposit, depositData
        );
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, depositPublicValues.oldRoot, depositPublicValues.newRoot);
        SuccinctVApp(VAPP).step(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw
        vm.startPrank(REQUESTER_2);
        bytes memory withdrawData = abi.encode(Withdraw({account: REQUESTER_2, amount: amount}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionPending(2, TransactionVariant.Withdraw, withdrawData);
        uint64 withdrawReceipt = SuccinctVApp(VAPP).requestWithdraw(REQUESTER_2, amount);
        vm.stopPrank();

        assertEq(withdrawReceipt, 2);
        (TransactionVariant actionType, TransactionStatus status,, bytes memory data) =
            SuccinctVApp(VAPP).transactions(withdrawReceipt);
        assertEq(uint8(actionType), uint8(TransactionVariant.Withdraw));
        assertEq(uint8(status), uint8(TransactionStatus.Pending));
        assertEq(data, withdrawData);

        // Update state after withdraw
        StepPublicValues memory withdrawPublicValues = StepPublicValues({
            receipts: new TxReceipt[](1),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });
        withdrawPublicValues.receipts[0] = TxReceipt({
            variant: TransactionVariant.Withdraw,
            status: TransactionStatus.Completed,
            onchainTxId: withdrawReceipt,
            action: withdrawData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionCompleted(
            withdrawReceipt, TransactionVariant.Withdraw, withdrawData
        );
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, withdrawPublicValues.oldRoot, withdrawPublicValues.newRoot);
        SuccinctVApp(VAPP).step(abi.encode(withdrawPublicValues), jsonFixture.proof);

        // Verify withdrawal claims created
        assertEq(SuccinctVApp(VAPP).claimableWithdrawal(REQUESTER_2), amount);

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedOnchainTxId(), 2);

        // Claim withdrawal
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_2), 0);
        vm.startPrank(REQUESTER_2);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Withdrawal(REQUESTER_2, amount);
        uint256 claimedAmount = SuccinctVApp(VAPP).finishWithdraw(REQUESTER_2);
        vm.stopPrank();

        assertEq(claimedAmount, amount);
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_2), amount); // User2 now has the PROVE
        assertEq(SuccinctVApp(VAPP).claimableWithdrawal(REQUESTER_2), 0); // Claim is cleared

        // Reattempt claim
        vm.startPrank(REQUESTER_2);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.NoWithdrawalToClaim.selector));
        SuccinctVApp(VAPP).finishWithdraw(REQUESTER_2);
        vm.stopPrank();
    }

    function test_RevertWithdraw_WhenZeroAddress() public {
        uint256 amount = SuccinctVApp(VAPP).minDepositAmount();

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.ZeroAddress.selector));
        SuccinctVApp(VAPP).requestWithdraw(address(0), amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentOnchainTxId(), 0);
    }

    function test_RevertWithdraw_WhenBelowMinimum() public {
        uint256 withdrawAmount = SuccinctVApp(VAPP).minDepositAmount() / 2;

        // Try to withdraw below minimum
        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.TransferBelowMinimum.selector));
        SuccinctVApp(VAPP).requestWithdraw(REQUESTER_1, withdrawAmount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentOnchainTxId(), 0);
    }
}
