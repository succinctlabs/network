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

contract SuccinctVAppDepositTest is SuccinctVAppTest {
    function test_Deposit_WhenValid() public {
        uint256 amount = 100e6;
        MockERC20(PROVE).mint(address(this), amount);
        MockERC20(PROVE).approve(address(VAPP), amount);

        assertEq(MockERC20(PROVE).balanceOf(address(this)), amount);
        assertEq(MockERC20(PROVE).balanceOf(address(VAPP)), 0);
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
        (, ReceiptStatus status,,) = SuccinctVApp(VAPP).receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.None));

        // Deposit
        bytes memory data =
            abi.encode(DepositAction({account: address(this), token: PROVE, amount: amount}));
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(1, ActionType.Deposit, data);
        SuccinctVApp(VAPP).deposit(address(this), PROVE, amount);

        assertEq(MockERC20(PROVE).balanceOf(address(this)), 0);
        assertEq(MockERC20(PROVE).balanceOf(address(VAPP)), amount);
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 1);
        (, status,,) = SuccinctVApp(VAPP).receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));

        // Update state with deposit action
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues.actions[0] = Action({
            action: ActionType.Deposit,
            status: ReceiptStatus.Completed,
            receipt: 1,
            data: data
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptCompleted(1, ActionType.Deposit, data);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues.newRoot, publicValues.oldRoot);

        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).receipts(1);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 1);
    }

    function test_RevertDeposit_WhenZeroAddress() public {
        uint256 amount = 100e6;
        MockERC20(PROVE).mint(REQUESTER_1, amount);

        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(address(VAPP), amount);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.ZeroAddress.selector));
        SuccinctVApp(VAPP).deposit(address(0), PROVE, amount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertDeposit_WhenNonWhitelistedToken() public {
        // Create a new token that isn't whitelisted
        MockERC20 nonWhitelistedToken = new MockERC20("TEST", "TEST", 18);
        uint256 amount = 100e6; // 100 tokens

        nonWhitelistedToken.mint(REQUESTER_1, amount);

        vm.startPrank(REQUESTER_1);
        nonWhitelistedToken.approve(address(VAPP), amount);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.TokenNotWhitelisted.selector));
        SuccinctVApp(VAPP).deposit(REQUESTER_1, address(nonWhitelistedToken), amount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }

    function test_RevertDeposit_WhenBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 PROVE
        uint256 depositAmount = minAmount / 2; // 5 PROVE - below minimum

        // Set minimum amount
        SuccinctVApp(VAPP).setMinimumDeposit(PROVE, minAmount);

        // Try to deposit below minimum
        MockERC20(PROVE).mint(REQUESTER_1, depositAmount);

        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(address(VAPP), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.DepositBelowMinimum.selector));
        SuccinctVApp(VAPP).deposit(REQUESTER_1, PROVE, depositAmount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
    }
}
