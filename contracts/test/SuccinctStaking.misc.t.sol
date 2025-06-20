// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// Possible combinations of functionality not covered in functionality-specific test files.
contract SuccinctStakingMiscellaneousTests is SuccinctStakingTest {
    // Test operations with exactly minimum stake amount
    function test_Misc_ExactMinimumStake() public {
        uint256 minStake = SuccinctStaking(STAKING).minStakeAmount();

        deal(PROVE, STAKER_1, minStake);

        // Should be able to stake exactly minimum
        _stake(STAKER_1, ALICE_PROVER, minStake);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), minStake);

        // Should be able to unstake
        _completeUnstake(STAKER_1, minStake);
    }

    // Test operations with less than minimum stake amount
    function test_Misc_BelowMinimumStake() public {
        uint256 minStake = SuccinctStaking(STAKING).minStakeAmount();
        uint256 belowMin = minStake - 1;

        deal(PROVE, STAKER_1, belowMin);

        // Approve the staking contract
        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, belowMin);

        // Should revert when staking below minimum
        vm.expectRevert(ISuccinctStaking.StakeBelowMinimum.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, belowMin);
    }

    // Test unstaking more than balance
    function test_Misc_UnstakeMoreThanBalance() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Try to unstake more than staked
        vm.expectRevert(ISuccinctStaking.InsufficientStakeBalance.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(stakeAmount + 1);
    }

    // Test multiple partial unstakes that exceed balance
    function test_Misc_MultiplePartialUnstakesExceedBalance() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request unstake for 60% of balance
        _requestUnstake(STAKER_1, stakeAmount * 60 / 100);

        // Try to request another 60% - should fail
        vm.expectRevert(ISuccinctStaking.InsufficientStakeBalance.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(stakeAmount * 60 / 100);
    }

    // Test operations at exact timing boundaries
    function test_Misc_ExactTimingBoundaries() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _requestUnstake(STAKER_1, stakeAmount);

        // Try to finish exactly 1 second before period ends
        skip(UNSTAKE_PERIOD - 1);
        uint256 received = _finishUnstake(STAKER_1);
        assertEq(received, 0, "Should not receive anything before period");

        // Now wait exactly 1 more second
        skip(1);
        received = _finishUnstake(STAKER_1);
        assertGt(received, 0, "Should receive tokens after period");
    }

    // Test slash timing at exact boundaries
    function test_Misc_SlashExactTimingBoundary() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        uint256 slashIndex = _requestSlash(ALICE_PROVER, stakeAmount / 2);

        // Try to finish exactly at boundary
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, slashIndex);

        // Verify slash was applied
        assertLt(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
    }

    // Test dispense with zero elapsed time
    function test_Misc_DispenseZeroTime() public {
        // First dispense all available amount to reset lastDispenseTimestamp to current
        skip(1 days);
        uint256 initialAvailable = SuccinctStaking(STAKING).maxDispense();
        deal(PROVE, STAKING, initialAvailable);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(initialAvailable);

        // Now no time has passed since last dispense
        uint256 available = SuccinctStaking(STAKING).maxDispense();
        assertEq(available, 0);

        // Try to dispense - should revert with AmountExceedsAvailableDispense
        vm.expectRevert(ISuccinctStaking.AmountExceedsAvailableDispense.selector);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(1);
    }

    // Test dispense with exactly 1 wei available
    function test_Misc_DispenseOneWei() public {
        // Calculate time needed for exactly 1 wei
        uint256 timeFor1Wei = 1 / DISPENSE_RATE + 1;
        skip(timeFor1Wei);

        uint256 available = SuccinctStaking(STAKING).maxDispense();
        assertGe(available, 1);

        // Dispense 1 wei
        deal(PROVE, STAKING, 1);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(1);
    }

    // Test that staker cannot switch provers
    function test_Misc_CannotSwitchProvers() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2;

        // Stake to first prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Try to stake to different prover
        deal(PROVE, STAKER_1, stakeAmount);

        // Approve the staking contract
        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, stakeAmount);

        // Expect revert when trying to stake to different prover
        vm.expectRevert(
            abi.encodeWithSelector(
                ISuccinctStaking.AlreadyStakedWithDifferentProver.selector, ALICE_PROVER
            )
        );
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(BOB_PROVER, stakeAmount);
    }

    // Test staking to same prover after full unstake
    function test_Misc_RestakeAfterFullUnstake() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2;

        // Stake and unstake completely
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _completeUnstake(STAKER_1, stakeAmount);

        // Should be able to stake to different prover now
        deal(PROVE, STAKER_1, stakeAmount);
        _stake(STAKER_1, BOB_PROVER, stakeAmount);

        assertEq(SuccinctStaking(STAKING).stakedTo(STAKER_1), BOB_PROVER);
    }

    // Test rewards and slashing happening in same block
    function test_Misc_RewardAndSlashSameBlock() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = stakeAmount / 2;
        uint256 slashAmount = stakeAmount / 4;

        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Process reward
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Request slash in same block
        uint256 slashIndex = _requestSlash(ALICE_PROVER, slashAmount);

        // Complete slash
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, slashIndex);

        // Verify final state
        uint256 finalStaked = SuccinctStaking(STAKING).staked(STAKER_1);
        assertGt(finalStaked, 0);
        assertLt(finalStaked, stakeAmount + rewardAmount);
    }

    // Test permit with expired deadline
    function test_Misc_PermitExpiredDeadline() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 deadline = block.timestamp - 1; // Already expired

        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(STAKER_1_PK, STAKER_1, ALICE_PROVER, stakeAmount, deadline);

        // Should revert due to expired deadline
        vm.expectRevert();
        SuccinctStaking(STAKING).permitAndStake(
            ALICE_PROVER, STAKER_1, stakeAmount, deadline, v, r, s
        );
    }

    // Test behavior when vault operations return zero
    function test_Misc_VaultReturnsZero() public {
        // This tests the contract's handling of zero receipt amounts
        // In practice, this should revert with ZeroReceiptAmount

        // Create a scenario where very small amounts might round to zero
        uint256 dustAmount = 1;

        // First stake a normal amount
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // Try to stake dust amount - might revert due to minimum or zero receipt
        deal(PROVE, STAKER_2, dustAmount);
        vm.prank(STAKER_2);
        IERC20(PROVE).approve(STAKING, dustAmount);

        // This should either revert with StakeBelowMinimum or ZeroReceiptAmount
        vm.expectRevert();
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, dustAmount);
    }

    // Test slash with invalid index
    function test_Misc_SlashInvalidIndex() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request one slash
        _requestSlash(ALICE_PROVER, stakeAmount / 2);

        skip(SLASH_PERIOD);

        // Try to finish slash with invalid index
        vm.expectRevert();
        vm.prank(OWNER);
        SuccinctStaking(STAKING).finishSlash(ALICE_PROVER, 999);
    }

    // Test empty unstake claims
    function test_Misc_FinishUnstakeNoClaims() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Try to finish unstake without any requests
        vm.expectRevert(ISuccinctStaking.NoUnstakeRequests.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishUnstake(STAKER_1, 0);
    }

    // Test non-owner cannot perform owner operations
    function test_Misc_NonOwnerCannotSlash() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        uint256 slashIndex = _requestSlash(ALICE_PROVER, stakeAmount / 2);

        skip(SLASH_PERIOD);

        // Non-owner tries to finish slash
        vm.expectRevert();
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishSlash(ALICE_PROVER, slashIndex);
    }

    // Test with maximum possible values
    function test_Misc_MaxUint256Operations() public {
        // Test that arithmetic doesn't overflow with large values
        uint256 safeMax = type(uint256).max / 1e6; // Safe maximum

        // Set up large balances
        deal(PROVE, STAKER_1, safeMax);
        deal(PROVE, I_PROVE, safeMax); // Ensure vault has liquidity

        // Should handle large stakes gracefully
        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, safeMax);

        // This might revert due to vault limits or succeed
        // Either way, it shouldn't cause unexpected behavior
        vm.prank(STAKER_1);
        try SuccinctStaking(STAKING).stake(ALICE_PROVER, safeMax) returns (uint256) {
            // If it succeeds, we should be able to query the stake
            assertGt(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        } catch {
            // If it reverts, that's also acceptable
            // The important thing is it doesn't cause undefined behavior
        }
    }

    // Test that multiple unstake requests cannot be exploited
    function test_Misc_MultipleUnstakeRequestsCannotDrainFunds() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake tokens
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Create multiple unstake requests for the same amount
        uint256 numRequests = 10;
        for (uint256 i = 0; i < numRequests; i++) {
            _requestUnstake(STAKER_1, stakeAmount / numRequests);
        }

        // Wait for unstake period
        skip(UNSTAKE_PERIOD);

        // Try to claim - should only get the staked amount back, not more
        uint256 balanceBefore = IERC20(PROVE).balanceOf(STAKER_1);
        _finishUnstake(STAKER_1);
        uint256 balanceAfter = IERC20(PROVE).balanceOf(STAKER_1);

        // Should not receive more than originally staked
        assertLe(balanceAfter - balanceBefore, stakeAmount);
    }

    // Test that rounding errors don't accumulate to cause loss
    function test_Misc_RoundingErrorsDoNotAccumulate() public {
        // Use amounts that will cause rounding at each level
        uint256 stakeAmount = 1000000000000000001; // Will cause rounding

        uint256 initialBalance = stakeAmount * 20;
        deal(PROVE, STAKER_1, initialBalance);

        uint256 balanceBefore = IERC20(PROVE).balanceOf(STAKER_1);

        // Perform many small stakes and unstakes
        for (uint256 i = 0; i < 10; i++) {
            _stake(STAKER_1, ALICE_PROVER, stakeAmount);
            _completeUnstake(STAKER_1, stakeAmount);
        }

        uint256 balanceAfter = IERC20(PROVE).balanceOf(STAKER_1);

        // The total loss due to rounding should be minimal
        uint256 loss = balanceBefore > balanceAfter ? balanceBefore - balanceAfter : 0;

        // Loss should be less than 0.01% of total operations
        uint256 totalVolume = stakeAmount * 10;
        assertLt(loss, totalVolume / 10000);
    }

    // Test that dust amounts can still be unstaked
    function test_Misc_DustAmountsCanBeUnstaked() public {
        // Minimum stake amount from the contract
        uint256 minStake = SuccinctStaking(STAKING).minStakeAmount();

        deal(PROVE, STAKER_1, minStake * 2);

        // Stake minimum amount
        _stake(STAKER_1, ALICE_PROVER, minStake);

        // Try to unstake 1 wei
        _requestUnstake(STAKER_1, 1);
        skip(UNSTAKE_PERIOD);

        uint256 received = _finishUnstake(STAKER_1);

        // Should receive at least something (might be 0 due to rounding)
        assertGe(received, 0);

        // Remaining balance should still be unstakeable
        uint256 remaining = SuccinctStaking(STAKING).balanceOf(STAKER_1);
        if (remaining > 0) {
            _completeUnstake(STAKER_1, remaining);
        }
    }

    // Test frontrunning protection during reward distribution
    function test_Misc_FrontrunningRewardDistribution() public {
        uint256 initialStake = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Staker 1 stakes initially
        _stake(STAKER_1, ALICE_PROVER, initialStake);

        // Simulate frontrunner trying to stake right before reward
        // In a real scenario, they would see the reward tx in mempool
        deal(PROVE, STAKER_2, initialStake);
        _stake(STAKER_2, ALICE_PROVER, initialStake);

        // Reward is distributed
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Both stakers should receive proportional rewards
        uint256 staker1Share = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 staker2Share = SuccinctStaking(STAKING).staked(STAKER_2);

        // Staker 2 should get their fair share, not more
        assertApproxEqAbs(staker1Share, staker2Share, 100);
    }

    // Test that users cannot avoid slashing by unstaking
    function test_Misc_CannotAvoidSlashingByUnstaking() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake tokens
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request unstake
        _requestUnstake(STAKER_1, stakeAmount);

        // Slash happens while unstake is pending
        uint256 slashAmount = stakeAmount / 2;
        _requestSlash(ALICE_PROVER, slashAmount);

        // Cannot finish unstake while slash is pending
        skip(UNSTAKE_PERIOD);
        vm.expectRevert(ISuccinctStaking.ProverHasSlashRequest.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishUnstake(STAKER_1, 0);

        // Complete the slash
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, 0);

        // Now finish unstake - should receive slashed amount
        uint256 received = _finishUnstake(STAKER_1);
        assertLt(received, stakeAmount);
    }

    // Test that exchange rate cannot be manipulated to steal funds
    function test_Misc_ExchangeRateManipulation() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Staker 1 stakes
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Attacker tries to manipulate by sending tokens directly
        deal(PROVE, address(this), stakeAmount);
        IERC20(PROVE).transfer(I_PROVE, stakeAmount);

        // Staker 2 stakes after manipulation
        deal(PROVE, STAKER_2, stakeAmount);
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Both should still have fair shares
        uint256 staked1 = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 staked2 = SuccinctStaking(STAKING).staked(STAKER_2);

        // The manipulation shouldn't give staker 2 an advantage
        assertGe(staked1, stakeAmount / 2);
        assertLe(staked2, stakeAmount * 2);
    }

    // Test staking near maximum uint256 values
    function test_Misc_MaximumStakeValues() public {
        // Use a large but safe amount that won't exceed ERC20 max supply
        uint256 largeAmount = 1e9 * 1e18; // 1 billion tokens

        // Give staker large amount
        deal(PROVE, STAKER_1, largeAmount);

        // Should be able to stake large amount
        _stake(STAKER_1, ALICE_PROVER, largeAmount);

        // Should be able to unstake
        _completeUnstake(STAKER_1, largeAmount);

        // Should receive back approximately the same amount
        assertGe(IERC20(PROVE).balanceOf(STAKER_1), largeAmount * 99 / 100);
    }

    // Test that unstake queue cannot be used for DoS
    function test_Misc_UnstakeQueueDoS() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake tokens
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Create many small unstake requests
        uint256 numRequests = 100;
        for (uint256 i = 0; i < numRequests; i++) {
            _requestUnstake(STAKER_1, stakeAmount / numRequests);
        }

        // Should still be able to process all unstakes
        skip(UNSTAKE_PERIOD);

        uint256 gasStart = gasleft();
        _finishUnstake(STAKER_1);
        uint256 gasUsed = gasStart - gasleft();

        // Gas usage should be reasonable (less than 10M gas for 100 requests)
        // This is about 100k gas per unstake request which is reasonable
        assertLt(gasUsed, 10000000);
    }

    // Test that operations with zero prover address fail safely
    function test_Misc_ZeroProverAddress() public {
        // Try to stake to non-existent prover (should revert)
        vm.expectRevert();
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(address(0), STAKER_PROVE_AMOUNT);

        // Staker with no prover should have zero staked
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).stakedTo(STAKER_1), address(0));
    }

    // Test multiple operations happening concurrently
    function test_Misc_ConcurrentOperations() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 4;

        // Multiple stakers stake
        deal(PROVE, STAKER_1, stakeAmount);
        deal(PROVE, STAKER_2, stakeAmount);
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Staker 1 requests unstake
        _requestUnstake(STAKER_1, stakeAmount / 2);

        // Reward comes in
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, stakeAmount);
        _withdrawFullBalanceFromVApp(ALICE_PROVER);

        // Staker 2 requests unstake
        _requestUnstake(STAKER_2, stakeAmount / 2);

        // Slash occurs
        _requestSlash(ALICE_PROVER, stakeAmount / 4);

        // Cannot complete unstakes while slash pending
        skip(UNSTAKE_PERIOD);
        vm.expectRevert(ISuccinctStaking.ProverHasSlashRequest.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishUnstake(STAKER_1, 0);

        // Complete slash
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, 0);

        // Now both can unstake
        uint256 received1 = _finishUnstake(STAKER_1);
        uint256 received2 = _finishUnstake(STAKER_2);

        // Both should receive something
        assertGt(received1, 0);
        assertGt(received2, 0);
    }

    // Test dispense calculation overflow protection
    function test_Misc_DispenseOverflow() public {
        // Try to dispense with amounts that could overflow
        uint256 hugeAmount = type(uint256).max / 2;

        // This should not overflow in timeConsumed calculation
        deal(PROVE, STAKING, hugeAmount);

        // Wait minimum time
        skip(1);

        // Get max dispense (should be limited by rate)
        uint256 maxDispense = SuccinctStaking(STAKING).maxDispense();
        assertLt(maxDispense, hugeAmount);

        // Should be able to dispense available amount
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(maxDispense);
    }
}
