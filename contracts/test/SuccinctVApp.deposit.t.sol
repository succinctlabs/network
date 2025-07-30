// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {
    StepPublicValues,
    TransactionStatus,
    Receipt as TxReceipt,
    TransactionVariant,
    DepositAction
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {ERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract SuccinctVAppDepositTest is SuccinctVAppTest {
    function test_Deposit_WhenValid() public {
        uint256 amount = SuccinctVApp(VAPP).minDepositAmount();
        MockERC20(PROVE).mint(REQUESTER_1, amount);

        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_1), amount);
        assertEq(MockERC20(PROVE).balanceOf(VAPP), 0);
        assertEq(SuccinctVApp(VAPP).currentOnchainTxId(), 0);
        (, TransactionStatus status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.None));

        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(VAPP, amount);

        // Deposit
        bytes memory data = abi.encode(DepositAction({account: REQUESTER_1, amount: amount}));
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionPending(1, TransactionVariant.Deposit, data);
        SuccinctVApp(VAPP).deposit(amount);
        vm.stopPrank();

        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_1), 0);
        assertEq(MockERC20(PROVE).balanceOf(VAPP), amount);
        assertEq(SuccinctVApp(VAPP).currentOnchainTxId(), 1);
        (, status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.Pending));

        // Update state with deposit action
        StepPublicValues memory publicValues = StepPublicValues({
            receipts: new TxReceipt[](1),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues.receipts[0] = TxReceipt({
            variant: TransactionVariant.Deposit,
            status: TransactionStatus.Completed,
            onchainTxId: 1,
            action: data
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionCompleted(1, TransactionVariant.Deposit, data);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues.oldRoot, publicValues.newRoot);

        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedOnchainTxId(), 1);
    }

    function test_PermitAndDeposit_WhenValid() public {
        uint256 amount = SuccinctVApp(VAPP).minDepositAmount();
        MockERC20(PROVE).mint(REQUESTER_1, amount);

        // Deposit
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(REQUESTER_1_PK, REQUESTER_1, amount, block.timestamp + 1 days);
        bytes memory data = abi.encode(DepositAction({account: REQUESTER_1, amount: amount}));
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionPending(1, TransactionVariant.Deposit, data);
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).permitAndDeposit(REQUESTER_1, amount, block.timestamp + 1 days, v, r, s);

        assertEq(MockERC20(PROVE).balanceOf(REQUESTER_1), 0);
        assertEq(MockERC20(PROVE).balanceOf(VAPP), amount);
        assertEq(SuccinctVApp(VAPP).currentOnchainTxId(), 1);
        (, TransactionStatus status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.Pending));

        // Update state with deposit action
        StepPublicValues memory publicValues = StepPublicValues({
            receipts: new TxReceipt[](1),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues.receipts[0] = TxReceipt({
            variant: TransactionVariant.Deposit,
            status: TransactionStatus.Completed,
            onchainTxId: 1,
            action: data
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.TransactionCompleted(1, TransactionVariant.Deposit, data);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues.oldRoot, publicValues.newRoot);

        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).transactions(1);
        assertEq(uint8(status), uint8(TransactionStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedOnchainTxId(), 1);
    }

    // An attacker frontrun by spending a depositor's permit signature, but because the allowance
    // equalling the amount being deposited skips the PROVE.permit() call, this does not block the
    // SuccinctVApp.permitAndDeposit() call.
    function test_PermitAndDeposit_WhenAttackerFrontruns() public {
        uint256 depositAmount = SuccinctVApp(VAPP).minDepositAmount();
        MockERC20(PROVE).mint(REQUESTER_1, depositAmount);

        uint256 deadline = block.timestamp + 1 days;

        // Staker signs a permit for the amount than they intend to deposit.
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(REQUESTER_1_PK, REQUESTER_1, depositAmount, deadline);

        // An attacker spends the permit (simulating a frontrun).
        vm.prank(OWNER);
        ERC20Permit(PROVE).permit(REQUESTER_1, VAPP, depositAmount, deadline, v, r, s);

        // The deposit still succeeds because permit is now skipped.
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).permitAndDeposit(REQUESTER_1, depositAmount, deadline, v, r, s);
    }

    function test_RevertDeposit_WhenBelowMinimum() public {
        uint256 depositAmount = SuccinctVApp(VAPP).minDepositAmount() / 2;

        // Try to deposit below minimum
        MockERC20(PROVE).mint(REQUESTER_1, depositAmount);

        vm.startPrank(REQUESTER_1);
        MockERC20(PROVE).approve(VAPP, depositAmount);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.TransferBelowMinimum.selector));
        SuccinctVApp(VAPP).deposit(depositAmount);
        vm.stopPrank();

        // Verify no deposit receipt was created
        assertEq(SuccinctVApp(VAPP).currentOnchainTxId(), 0);
    }
}
