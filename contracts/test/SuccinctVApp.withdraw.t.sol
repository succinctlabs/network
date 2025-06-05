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
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract SuccinctVAppWithdrawTest is SuccinctVAppTest {
    function test_Withdraw_WhenValid() public {
        uint256 amount = 100e6; // 100 PROVE (6 decimals)

        // Deposit
        MockERC20(PROVE).mint(REQUESTER_1, amount);
        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(VAPP, amount);
        uint64 depositReceipt = SuccinctVApp(VAPP).deposit(amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(Deposit({account: REQUESTER_1, amount: amount}));
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
        emit ISuccinctVApp.Block(1, depositPublicValues.newRoot, depositPublicValues.oldRoot);
        SuccinctVApp(VAPP).step(abi.encode(depositPublicValues), jsonFixture.proof);

        // Withdraw
        vm.startPrank(REQUESTER_2);
        bytes memory withdrawData =
            abi.encode(Withdraw({account: REQUESTER_2, amount: amount}));

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
        emit ISuccinctVApp.Block(2, withdrawPublicValues.newRoot, withdrawPublicValues.oldRoot);
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

    function test_WithdrawTo_WhenValid() public {
        uint256 amount = 100e6; // 100 PROVE (6 decimals)

        // Deposit
        MockERC20(PROVE).mint(REQUESTER_1, amount);
        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(VAPP, amount);
        uint64 depositReceipt = SuccinctVApp(VAPP).deposit(amount);
        vm.stopPrank();

        // Update state after deposit
        bytes memory depositData =
            abi.encode(Deposit({account: REQUESTER_1, amount: amount}));
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
        emit ISuccinctVApp.Block(1, depositPublicValues.newRoot, depositPublicValues.oldRoot);

        SuccinctVApp(VAPP).step(abi.encode(depositPublicValues), jsonFixture.proof);

        // TODO
    }

    function test_RevertWithdraw_WhenZeroAddress() public {
        uint256 amount = 100e6;

        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.ZeroAddress.selector));
        SuccinctVApp(VAPP).requestWithdraw(address(0), amount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentOnchainTxId(), 0);
    }

    function test_RevertWithdraw_WhenBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 PROVE
        uint256 withdrawAmount = 5e6; // 5 PROVE - below minimum

        // Set minimum amount
        SuccinctVApp(VAPP).updateMinDepositAmount(minAmount);

        // Try to withdraw below minimum
        vm.startPrank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.TransferBelowMinimum.selector));
        SuccinctVApp(VAPP).requestWithdraw(REQUESTER_1, withdrawAmount);
        vm.stopPrank();

        // Verify no withdrawal receipt was created
        assertEq(SuccinctVApp(VAPP).currentOnchainTxId(), 0);
    }

    // TODO: This worked when multiple tokens (e.g. USDC) were supported, but since
    // converting it to PROVE, we need to update the test.

    // function test_EmergencyWithdrawal_WhenValid() public {
    //     mockCall(true);

    //     // Failover so that we can use the hardcoded usdc in the merkle root
    //     address testUsdc = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;
    //     if (testUsdc != PROVE) {
    //         // vm.store(VAPP, bytes32(uint256(0)), bytes32(uint256(uint160(testUsdc))));
    //         vm.etch(testUsdc, PROVE.code);
    //     }
    //     MockERC20(testUsdc).mint(address(this), 100);
    //     MockERC20(testUsdc).approve(VAPP, 100);
    //     SuccinctVApp(VAPP).deposit(address(this), 100);

    //     // The merkle tree
    //     bytes32 root = 0xc53421d840beb11a0382b8d5bbf524da79ddb96b11792c3812276a05300e276e;
    //     bytes32[] memory proof = new bytes32[](4);
    //     proof[0] = 0x97166dee2bb3b38545a732e4fc42a7d745eaeb55be08c08b7dfad28961af339b;
    //     proof[1] = 0xd530f51fd96943359dc951ce6d19212cc540a321562a0bcd7e1747700dce0ec9;
    //     proof[2] = 0x5517ae9ffdaac5507c9bc6990aa6637b3ce06ebfbdb08f4208c73dc2fe2d20a9;
    //     proof[3] = 0x35b34cde80bb3bd84dbd6d84ccfa8b739908f2c632802af348512215e8eb7dd6;

    //     PublicValuesStruct memory publicValues = PublicValuesStruct({
    //         actions: new Action[](0),
    //         oldRoot: bytes32(0),
    //         newRoot: root,
    //         timestamp: uint64(block.timestamp)
    //     });
    //     SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

    //     vm.warp(block.timestamp + SuccinctVApp(VAPP).freezeDuration() + 1);

    //     address user = 0x4F06869E36F2De69d97e636E52B45F07A91b4fa6;

    //     // Withdraw
    //     vm.startPrank(user);
    //     SuccinctVApp(VAPP).emergencyWithdraw(100, proof);

    //     // Claim withdrawal
    //     assertEq(ERC20(testUsdc).balanceOf(user), 0);
    //     SuccinctVApp(VAPP).finishWithdraw(user);
    //     assertEq(ERC20(testUsdc).balanceOf(user), 100);
    //     vm.stopPrank();
    // }
}
