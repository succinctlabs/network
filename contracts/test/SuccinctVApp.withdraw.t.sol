// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Actions} from "../src/libraries/Actions.sol";
import {
    PublicValuesStruct,
    ReceiptStatus,
    Action,
    ActionType,
    DepositAction,
    WithdrawAction,
    AddSignerAction,
    RemoveSignerAction,
    SlashAction,
    RewardAction
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract SuccinctVAppWithdrawTest is SuccinctVAppTest {
    function test_Withdraw_WhenValid() public {
        uint256 amount = 100e6; // 100 PROVE (6 decimals)

        // Deposit
        MockERC20(PROVE).mint(REQUESTER_1, amount);
        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(address(VAPP), amount);
        uint64 depositReceipt = SuccinctVApp(VAPP).deposit(REQUESTER_1, PROVE, amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(DepositAction({account: REQUESTER_1, token: PROVE, amount: amount}));
        PublicValuesStruct memory depositPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        depositPublicValues.actions[0] = Action({
            action: ActionType.Deposit,
            status: ReceiptStatus.Completed,
            receipt: depositReceipt,
            data: depositData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(depositReceipt, ActionType.Deposit, depositData);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, depositPublicValues.newRoot, depositPublicValues.oldRoot);
        SuccinctVApp(VAPP).updateState(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw
        vm.startPrank(REQUESTER_2);
        bytes memory withdrawData = abi.encode(
            WithdrawAction({account: REQUESTER_2, token: PROVE, amount: amount, to: REQUESTER_2})
        );

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.Withdraw, withdrawData);
        uint64 withdrawReceipt = SuccinctVApp(VAPP).withdraw(REQUESTER_2, PROVE, amount);
        vm.stopPrank();

        assertEq(withdrawReceipt, 2);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(VAPP).receipts(withdrawReceipt);
        assertEq(uint8(actionType), uint8(ActionType.Withdraw));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, withdrawData);

        // Update state after withdraw
        PublicValuesStruct memory withdrawPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });
        withdrawPublicValues.actions[0] = Action({
            action: ActionType.Withdraw,
            status: ReceiptStatus.Completed,
            receipt: withdrawReceipt,
            data: withdrawData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(withdrawReceipt, ActionType.Withdraw, withdrawData);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, withdrawPublicValues.newRoot, withdrawPublicValues.oldRoot);
        SuccinctVApp(VAPP).updateState(abi.encode(withdrawPublicValues), jsonFixture.proof);

        // Verify withdrawal claims created
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_2, PROVE), amount);
        assertEq(SuccinctVApp(VAPP).pendingWithdrawalClaims(PROVE), amount);

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 2);

        // Claim withdrawal
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_2), 0);
        vm.startPrank(REQUESTER_2);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.WithdrawalClaimed(REQUESTER_2, PROVE, REQUESTER_2, amount);
        uint256 claimedAmount = SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_2, PROVE);
        vm.stopPrank();

        assertEq(claimedAmount, amount);
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_2), amount); // User2 now has the PROVE
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_2, PROVE), 0); // Claim is cleared
        assertEq(SuccinctVApp(VAPP).pendingWithdrawalClaims(PROVE), 0); // No more pending claims

        // Reattempt claim
        vm.startPrank(REQUESTER_2);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.NoWithdrawalToClaim.selector));
        SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_2, PROVE);
        vm.stopPrank();
    }

    function test_WithdrawTo_WhenValid() public {
        uint256 amount = 100e6; // 100 PROVE (6 decimals)

        // Deposit
        MockERC20(PROVE).mint(REQUESTER_1, amount);
        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(address(VAPP), amount);
        uint64 depositReceipt = SuccinctVApp(VAPP).deposit(REQUESTER_1, PROVE, amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(DepositAction({account: REQUESTER_1, token: PROVE, amount: amount}));
        PublicValuesStruct memory depositPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        depositPublicValues.actions[0] = Action({
            action: ActionType.Deposit,
            status: ReceiptStatus.Completed,
            receipt: depositReceipt,
            data: depositData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(depositReceipt, ActionType.Deposit, depositData);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, depositPublicValues.newRoot, depositPublicValues.oldRoot);
        SuccinctVApp(VAPP).updateState(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw with a different recipient (user2 initiates withdrawal to user3)
        vm.startPrank(REQUESTER_2);
        bytes memory withdrawData = abi.encode(
            WithdrawAction({account: REQUESTER_2, token: PROVE, amount: amount, to: REQUESTER_3})
        );

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.Withdraw, withdrawData);
        uint64 withdrawReceipt = SuccinctVApp(VAPP).withdraw(REQUESTER_3, PROVE, amount);
        vm.stopPrank();

        assertEq(withdrawReceipt, 2);
        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(VAPP).receipts(withdrawReceipt);
        assertEq(uint8(actionType), uint8(ActionType.Withdraw));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, withdrawData);

        // Update state after withdraw
        PublicValuesStruct memory withdrawPublicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });
        withdrawPublicValues.actions[0] = Action({
            action: ActionType.Withdraw,
            status: ReceiptStatus.Completed,
            receipt: withdrawReceipt,
            data: withdrawData
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(withdrawReceipt, ActionType.Withdraw, withdrawData);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, withdrawPublicValues.newRoot, withdrawPublicValues.oldRoot);
        SuccinctVApp(VAPP).updateState(abi.encode(withdrawPublicValues), jsonFixture.proof);

        // Verify withdrawal claim was created for user3, not user2
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_2, PROVE), 0);
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_3, PROVE), amount);
        assertEq(SuccinctVApp(VAPP).pendingWithdrawalClaims(PROVE), amount);

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 2);

        // Claim withdrawal as user3
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_3), 0);
        vm.startPrank(REQUESTER_3);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.WithdrawalClaimed(REQUESTER_3, PROVE, REQUESTER_3, amount);
        uint256 claimedAmount = SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_3, PROVE);
        vm.stopPrank();

        // Verify claim was successful, and user3 has the funds
        assertEq(claimedAmount, amount);
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_3), amount); // User3 now has the PROVE
        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_2), 0); // User2 has nothing
        assertEq(SuccinctVApp(VAPP).withdrawalClaims(REQUESTER_3, PROVE), 0); // Claim is cleared
        assertEq(SuccinctVApp(VAPP).pendingWithdrawalClaims(PROVE), 0); // No more pending claims

        // Attempt to claim again should fail
        vm.startPrank(REQUESTER_3);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.NoWithdrawalToClaim.selector));
        SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_3, PROVE);
        vm.stopPrank();

        // User2 shouldn't be able to claim either
        vm.startPrank(REQUESTER_2);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.NoWithdrawalToClaim.selector));
        SuccinctVApp(VAPP).claimWithdrawal(REQUESTER_2, PROVE);
        vm.stopPrank();
    }

    function test_RevertWithdraw_WhenZeroAddress() public {
        uint256 amount = 100e6;

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.ZeroAddress.selector));
        SuccinctVApp(VAPP).withdraw(address(0), PROVE, amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertWithdraw_WhenNonWhitelistedToken() public {
        // Create a new token that isn't whitelisted
        MockERC20 nonWhitelistedToken = new MockERC20("TEST", "TEST", 18);
        uint256 amount = 100e6; // 100 tokens

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.TokenNotWhitelisted.selector));
        SuccinctVApp(VAPP).withdraw(REQUESTER_1, address(nonWhitelistedToken), amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertWithdraw_WhenBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 PROVE
        uint256 withdrawAmount = 5e6; // 5 PROVE - below minimum

        // Set minimum amount
        SuccinctVApp(VAPP).setMinimumDeposit(PROVE, minAmount);

        // Try to withdraw below minimum
        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.DepositBelowMinimum.selector));
        SuccinctVApp(VAPP).withdraw(REQUESTER_1, PROVE, withdrawAmount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_EmergencyWithdrawal_WhenValid() public {
        mockCall(true);

        // Failover so that we can use the hardcoded usdc in the merkle root
        address testUsdc = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;
        if (testUsdc != PROVE) {
            vm.etch(testUsdc, PROVE.code);
            SuccinctVApp(VAPP).addToken(testUsdc);
        }
        MockERC20(testUsdc).mint(address(this), 100);
        MockERC20(testUsdc).approve(address(VAPP), 100);
        SuccinctVApp(VAPP).deposit(address(this), address(testUsdc), 100);

        // The merkle tree
        bytes32 root = 0xc53421d840beb11a0382b8d5bbf524da79ddb96b11792c3812276a05300e276e;
        bytes32[] memory proof = new bytes32[](4);
        proof[0] = 0x97166dee2bb3b38545a732e4fc42a7d745eaeb55be08c08b7dfad28961af339b;
        proof[1] = 0xd530f51fd96943359dc951ce6d19212cc540a321562a0bcd7e1747700dce0ec9;
        proof[2] = 0x5517ae9ffdaac5507c9bc6990aa6637b3ce06ebfbdb08f4208c73dc2fe2d20a9;
        proof[3] = 0x35b34cde80bb3bd84dbd6d84ccfa8b739908f2c632802af348512215e8eb7dd6;

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: root,
            timestamp: uint64(block.timestamp)
        });
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

        vm.warp(block.timestamp + SuccinctVApp(VAPP).freezeDuration() + 1);

        address user = 0x4F06869E36F2De69d97e636E52B45F07A91b4fa6;

        // Withdraw
        vm.startPrank(user);
        SuccinctVApp(VAPP).emergencyWithdraw(address(testUsdc), 100, proof);

        // Claim withdrawal
        assertEq(ERC20(testUsdc).balanceOf(user), 0);
        SuccinctVApp(VAPP).claimWithdrawal(user, address(testUsdc));
        assertEq(ERC20(testUsdc).balanceOf(user), 100);
        vm.stopPrank();
    }
}
