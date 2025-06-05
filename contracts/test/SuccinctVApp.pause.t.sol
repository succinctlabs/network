// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {
    StepPublicValues,
    TransactionStatus,
    Receipt,
    TransactionVariant,
    Deposit,
    Withdraw,
    CreateProver
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {PausableUpgradeable} from
    "../lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";

// Tests that functions that are marked as whenNotPaused revert when paused.
contract SuccinctVAppPauseTest is SuccinctVAppTest {
    function test_RevertDeposit_WhenPaused() public {
        uint256 amount = SuccinctVApp(VAPP).minDepositAmount();

        vm.prank(OWNER);
        SuccinctVApp(VAPP).pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).deposit(amount);
    }

    function test_RevertRequestWithdrawal_WhenPaused() public {
        uint256 amount = SuccinctVApp(VAPP).minDepositAmount();

        vm.prank(OWNER);
        SuccinctVApp(VAPP).pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).requestWithdraw(REQUESTER_1, amount);
    }

    function test_RevertFinishWithdrawal_WhenPaused() public {
        vm.prank(OWNER);
        SuccinctVApp(VAPP).pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).finishWithdraw(REQUESTER_1);
    }

    function test_RevertCreateProver_WhenPaused() public {
        vm.prank(OWNER);
        SuccinctVApp(VAPP).pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(REQUESTER_1);
        ISuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);
    }

    function test_RevertStep_WhenPaused() public {
        vm.prank(OWNER);
        SuccinctVApp(VAPP).pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).step(hex"00", hex"00");
    }
}
