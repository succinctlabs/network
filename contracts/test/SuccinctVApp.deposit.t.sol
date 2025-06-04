// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Receipts} from "../src/libraries/Receipts.sol";
import {
    PublicValuesStruct,
    TransactionStatus,
    Receipt as TxReceipt,
    TransactionVariant,
    DepositTransaction,
    WithdrawTransaction,
    CreateProverTransaction
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract SuccinctVAppDepositTest is SuccinctVAppTest {
    function test_Deposit_WhenValid() public {
        uint256 amount = 100e6;
        MockERC20(PROVE).mint(REQUESTER_1, amount);

        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_1), amount);
        assertEq(MockERC20(PROVE).balanceOf(VAPP), 0);
        assertEq(SuccinctVApp(VAPP).currentOnchainTx(), 0);
        (, TransactionStatus status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.None));

        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(VAPP, amount);

        // Deposit
        bytes memory data = abi.encode(DepositTransaction({account: REQUESTER_1, amount: amount}));
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionPending(1, TransactionVariant.Deposit, data);
        SuccinctVApp(VAPP).deposit(amount);
        vm.stopPrank();

        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_1), 0);
        assertEq(MockERC20(PROVE).balanceOf(VAPP), amount);
        assertEq(SuccinctVApp(VAPP).currentOnchainTx(), 1);
        (, status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.Pending));

        // Update state with deposit action
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            txId: 1,
            receipts: new TxReceipt[](1),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues.receipts[0] = TxReceipt({
            variant: TransactionVariant.Deposit,
            status: TransactionStatus.Completed,
            onchainTx: 1,
            data: data
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionCompleted(1, TransactionVariant.Deposit, data);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues.newRoot, publicValues.oldRoot);

        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedOnchainTx(), 1);
    }

    function test_PermitAndDeposit_WhenValid() public {
        uint256 amount = 100e6;
        MockERC20(PROVE).mint(REQUESTER_1, amount);

        // Deposit
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(REQUESTER_1_PK, REQUESTER_1, amount, block.timestamp + 1 days);
        bytes memory data = abi.encode(DepositTransaction({account: REQUESTER_1, amount: amount}));
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionPending(1, TransactionVariant.Deposit, data);
        SuccinctVApp(VAPP).permitAndDeposit(REQUESTER_1, amount, block.timestamp + 1 days, v, r, s);

        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_1), 0);
        assertEq(MockERC20(PROVE).balanceOf(VAPP), amount);
        assertEq(SuccinctVApp(VAPP).currentOnchainTx(), 1);
        (, TransactionStatus status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.Pending));

        // Update state with deposit action
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            txId: 1,
            receipts: new TxReceipt[](1),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues.receipts[0] = TxReceipt({
            variant: TransactionVariant.Deposit,
            status: TransactionStatus.Completed,
            onchainTx: 1,
            data: data
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionCompleted(1, TransactionVariant.Deposit, data);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues.newRoot, publicValues.oldRoot);

        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedOnchainTx(), 1);
    }

    function test_RevertDeposit_WhenBelowMinimum() public {
        uint256 minAmount = 10e6; // 10 PROVE
        uint256 depositAmount = minAmount / 2; // 5 PROVE - below minimum

        // Set minimum amount
        SuccinctVApp(VAPP).updateMinDepositAmount(minAmount);

        // Try to deposit below minimum
        MockERC20(PROVE).mint(REQUESTER_1, depositAmount);

        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(VAPP, depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.TransferBelowMinimum.selector));
        SuccinctVApp(VAPP).deposit(depositAmount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(VAPP).currentOnchainTx(), 0);
    }
}
