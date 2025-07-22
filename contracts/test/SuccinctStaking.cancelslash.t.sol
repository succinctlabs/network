// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {SuccinctGovernor} from "../src/SuccinctGovernor.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";

contract SuccinctStakingCancelSlashTests is SuccinctStakingTest {
    function setUp() public override {
        super.setUp();

        // Stake to both provers for testing.
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);
        _stake(STAKER_2, BOB_PROVER, STAKER_PROVE_AMOUNT);
    }

    function test_CancelSlash_WhenAfterDeadline() public {
        // Request a slash.
        uint256 index = _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        // Get governance parameters.
        uint256 votingDelay = SuccinctGovernor(payable(GOVERNOR)).votingDelay();
        uint256 votingPeriod = SuccinctGovernor(payable(GOVERNOR)).votingPeriod();

        // Calculate total time needed.
        uint256 totalWaitTime = SLASH_CANCELLATION_PERIOD + votingDelay + votingPeriod;

        // Wait the full required time.
        skip(totalWaitTime);

        // Anyone can cancel after deadline.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index);

        // Verify the slash is marked as resolved.
        ISuccinctStaking.SlashClaim[] memory slashRequests =
            SuccinctStaking(STAKING).slashRequests(ALICE_PROVER);
        assertTrue(slashRequests[index].resolved);
    }

    function test_RevertCancelSlash_WhenNonOwnerCancelsEarly() public {
        // Request a slash.
        uint256 index = _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        // Get governance parameters.
        uint256 votingDelay = SuccinctGovernor(payable(GOVERNOR)).votingDelay();
        uint256 votingPeriod = SuccinctGovernor(payable(GOVERNOR)).votingPeriod();

        // Calculate total time needed (but don't wait that long).
        uint256 totalWaitTime = SLASH_CANCELLATION_PERIOD + votingDelay + votingPeriod;

        // Wait just short of the required time.
        skip(totalWaitTime - 1);

        // Non-owner should not be able to cancel yet.
        vm.expectRevert(ISuccinctStaking.SlashRequestNotReadyToCancel.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index);
    }

    function test_CancelSlash_WhenNonOwnerCancelsAfterDeadline() public {
        // Request a slash.
        uint256 index = _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        // Get governance parameters.
        uint256 votingDelay = SuccinctGovernor(payable(GOVERNOR)).votingDelay();
        uint256 votingPeriod = SuccinctGovernor(payable(GOVERNOR)).votingPeriod();

        // Calculate total time needed.
        uint256 totalWaitTime = SLASH_CANCELLATION_PERIOD + votingDelay + votingPeriod;

        // Wait the full required time.
        skip(totalWaitTime);

        // Non-owner should now be able to cancel.
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index);

        // Verify the slash is marked as resolved.
        ISuccinctStaking.SlashClaim[] memory slashRequests =
            SuccinctStaking(STAKING).slashRequests(ALICE_PROVER);
        assertTrue(slashRequests[index].resolved);
    }

    function test_RevertCancelSlash_WhenAlreadyResolved() public {
        // Request a slash.
        uint256 index = _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        // Get governance parameters.
        uint256 votingDelay = SuccinctGovernor(payable(GOVERNOR)).votingDelay();
        uint256 votingPeriod = SuccinctGovernor(payable(GOVERNOR)).votingPeriod();

        // Wait for the deadline.
        uint256 totalWaitTime = SLASH_CANCELLATION_PERIOD + votingDelay + votingPeriod;
        skip(totalWaitTime);

        // Cancel the slash.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index);

        // Try to cancel again - should revert.
        vm.expectRevert(ISuccinctStaking.SlashRequestAlreadyResolved.selector);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index);
    }

    function test_CancelSlash_WhenGovernanceCanFinishImmediately() public {
        // Request a slash.
        uint256 index = _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        // Owner (governance) can finish the slash immediately.
        vm.prank(OWNER);
        uint256 slashed = SuccinctStaking(STAKING).finishSlash(ALICE_PROVER, index);

        // Verify slash was executed.
        assertGt(slashed, 0);

        // Verify the slash is marked as resolved.
        ISuccinctStaking.SlashClaim[] memory slashRequests =
            SuccinctStaking(STAKING).slashRequests(ALICE_PROVER);
        assertTrue(slashRequests[index].resolved);
    }

    function test_CancelSlash_WhenStakersCanUnstakeAfterCancellation() public {
        // Request an unstake before slash.
        _requestUnstake(STAKER_1, STAKER_PROVE_AMOUNT / 4);

        // Request a slash.
        uint256 index = _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        // Try to finish unstake - should fail due to pending slash.
        vm.expectRevert(ISuccinctStaking.ProverHasSlashRequest.selector);
        _finishUnstake(STAKER_1);

        // Get governance parameters.
        uint256 votingDelay = SuccinctGovernor(payable(GOVERNOR)).votingDelay();
        uint256 votingPeriod = SuccinctGovernor(payable(GOVERNOR)).votingPeriod();

        // Wait for the full cancellation period.
        uint256 totalWaitTime = SLASH_CANCELLATION_PERIOD + votingDelay + votingPeriod;
        skip(totalWaitTime);

        // Anyone can cancel the slash now.
        vm.prank(makeAddr("RANDOM_USER"));
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index);

        // Wait for unstake period to complete (if needed).
        skip(UNSTAKE_PERIOD);

        // Now stakers should be able to finish unstaking.
        uint256 unstaked = _finishUnstake(STAKER_1);
        assertGt(unstaked, 0);
    }

    function test_CancelSlash_WhenExactBoundaryTiming() public {
        // Request a slash.
        uint256 index = _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        // Get governance parameters.
        uint256 votingDelay = SuccinctGovernor(payable(GOVERNOR)).votingDelay();
        uint256 votingPeriod = SuccinctGovernor(payable(GOVERNOR)).votingPeriod();

        // Calculate exact deadline.
        uint256 totalWaitTime = SLASH_CANCELLATION_PERIOD + votingDelay + votingPeriod;

        // Test exactly at the boundary - 1 second.
        skip(totalWaitTime - 1);

        // Should still fail.
        vm.expectRevert(ISuccinctStaking.SlashRequestNotReadyToCancel.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index);

        // Skip one more second to exactly hit the boundary.
        skip(1);

        // Should now succeed.
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index);
    }

    function test_CancelSlash_WhenMultipleSlashesCanBeCancelledIndependently() public {
        // Request multiple slashes at different times.
        uint256 index1 = _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 4);
        skip(1 days);
        uint256 index2 = _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 4);

        // Get governance parameters.
        uint256 votingDelay = SuccinctGovernor(payable(GOVERNOR)).votingDelay();
        uint256 votingPeriod = SuccinctGovernor(payable(GOVERNOR)).votingPeriod();
        uint256 totalWaitTime = SLASH_CANCELLATION_PERIOD + votingDelay + votingPeriod;

        // Wait until first slash can be cancelled but not the second.
        skip(totalWaitTime - 1 days);

        // First slash can be cancelled by anyone.
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index1);

        // Second slash cannot be cancelled yet.
        vm.expectRevert(ISuccinctStaking.SlashRequestNotReadyToCancel.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index2);

        // Wait the remaining day.
        skip(1 days);

        // Now second slash can be cancelled.
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, index2);
    }
}
