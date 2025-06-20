// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IERC20Errors} from "../lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

contract SuccinctStakingDispenseTests is SuccinctStakingTest {
    // A staker unstakes after a dispense occured should give them additional $PROVE
    function test_Dispense_WhenValid() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 dispenseAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Check state after staking
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);

        // Dispense
        _dispense(dispenseAmount);

        // Verify rewards were distributed
        // balanceOf increases because there is more $PROVE underlying per $stPROVE
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        // staked increases because the redemption value is higher
        // Note: We allow for 1 wei rounding error due to ERC4626 vault calculations
        uint256 expectedStakedAfterDispense = stakeAmount + dispenseAmount;
        uint256 actualStaked = SuccinctStaking(STAKING).staked(STAKER_1);
        assertApproxEqAbs(actualStaked, expectedStakedAfterDispense, 10);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount + dispenseAmount);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);

        // All $PROVE should be returned to the staker (minus potential rounding)
        assertApproxEqAbs(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount + dispenseAmount, 10);
        assertApproxEqAbs(IERC20(PROVE).balanceOf(I_PROVE), 0, 10);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
    }

    // Dispense when no stake in the contract should still work
    function test_Dispense_WhenNoStake() public {
        uint256 dispenseAmount = STAKER_PROVE_AMOUNT;

        // Dispense
        _dispense(dispenseAmount);

        // Verify rewards were distributed
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), dispenseAmount);
    }

    // Ensure dispense rate is properly enforced
    function test_Dispense_WhenRateLimit() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Try to dispense more than allowed amount (should fail)
        uint256 excessAmount = DISPENSE_RATE * 10;
        vm.expectRevert(ISuccinctStaking.AmountExceedsAvailableDispense.selector);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(excessAmount);

        // Wait a bit of time
        uint256 waitTime = 5 days;
        skip(waitTime);

        // Check max dispense available
        uint256 maxAmount = SuccinctStaking(STAKING).maxDispense();
        assertEq(maxAmount, waitTime * DISPENSE_RATE);

        // Mint PROVE tokens to the SuccinctStaking contract for dispensing
        deal(PROVE, STAKING, maxAmount);

        // Dispense half of the available amount
        uint256 halfAmount = maxAmount / 2;
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(halfAmount);

        // Check that maxDispense was updated correctly
        assertEq(SuccinctStaking(STAKING).maxDispense(), maxAmount - halfAmount);

        // Dispense remaining amount
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(maxAmount - halfAmount);

        // Check that maxDispense is now 0
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);

        // Try to dispense again (should fail)
        vm.expectRevert(ISuccinctStaking.AmountExceedsAvailableDispense.selector);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(1);
    }

    // Consecutive dispenses with waiting periods
    function test_Dispense_WhenConsecutiveWithWaiting() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // First dispense: wait for time to accumulate
        uint256 firstWaitTime = 3 days;
        skip(firstWaitTime);

        // Calculate available amount
        uint256 firstAvailable = SuccinctStaking(STAKING).maxDispense();
        assertEq(firstAvailable, firstWaitTime * DISPENSE_RATE);

        // Dispense half of the available amount
        uint256 firstDispenseAmount = firstAvailable / 2;
        deal(PROVE, STAKING, firstDispenseAmount);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(firstDispenseAmount);

        // Check remaining available after first dispense
        assertEq(SuccinctStaking(STAKING).maxDispense(), firstAvailable - firstDispenseAmount);

        // Wait for more time to accumulate
        uint256 secondWaitTime = 5 days;
        skip(secondWaitTime);

        // Calculate newly available amount (remaining from first + accumulated during second wait)
        uint256 expectedNewlyAvailable =
            (firstAvailable - firstDispenseAmount) + (secondWaitTime * DISPENSE_RATE);
        assertEq(SuccinctStaking(STAKING).maxDispense(), expectedNewlyAvailable);

        // Dispense everything available
        deal(PROVE, STAKING, expectedNewlyAvailable);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(expectedNewlyAvailable);

        // Check available is now 0
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);
    }

    // Dispensing exactly at the limit
    function test_Dispense_WhenExactLimit() public {
        // Stake some amount so we have assets in the system
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // Wait for time to accumulate
        uint256 waitTime = 3 days;
        skip(waitTime);

        // Get the exact available amount
        uint256 exactAmount = SuccinctStaking(STAKING).maxDispense();
        assertEq(exactAmount, waitTime * DISPENSE_RATE);

        // Dispense exactly the available amount
        deal(PROVE, STAKING, exactAmount);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(exactAmount);

        // The available amount should now be 0
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);

        // Trying to dispense any amount now should fail
        vm.expectRevert(ISuccinctStaking.AmountExceedsAvailableDispense.selector);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(1);
    }

    // Changing dispense rate and its effect on available amount
    function test_Dispense_WhenRateChangeEffects() public {
        // Stake some amount so we have assets in the system
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // Wait for time to accumulate
        uint256 initialWaitTime = 3 days;
        skip(initialWaitTime);

        // Get initial available amount
        uint256 initialAvailable = SuccinctStaking(STAKING).maxDispense();
        assertEq(initialAvailable, initialWaitTime * DISPENSE_RATE);

        // Dispense half of the available amount
        uint256 halfAmount = initialAvailable / 2;
        deal(PROVE, STAKING, halfAmount);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(halfAmount);

        // Change the dispense rate (double it)
        uint256 newRate = DISPENSE_RATE * 2;
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(newRate);

        // Wait for more time to accumulate with the new rate
        uint256 additionalWaitTime = 2 days;
        skip(additionalWaitTime);

        uint256 available = SuccinctStaking(STAKING).maxDispense();

        // Dispense again to verify it works with the new rate
        deal(PROVE, STAKING, available);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(available);

        // Available should now be 0
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);
    }

    // Dispense calculation with very large time periods
    function test_Dispense_WhenVeryLargeTimePeriod() public {
        // Stake some amount so we have assets in the system
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // Skip a very large amount of time (e.g., multiple years)
        uint256 veryLargeTime = 365 days * 5; // 5 years
        skip(veryLargeTime);

        // Calculate the expected max dispense
        uint256 expectedMax = veryLargeTime * DISPENSE_RATE;

        // Check that maxDispense works correctly with large time periods
        assertEq(SuccinctStaking(STAKING).maxDispense(), expectedMax);

        // Try dispensing a significant portion
        uint256 largeDispenseAmount = expectedMax / 2;
        deal(PROVE, STAKING, largeDispenseAmount);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(largeDispenseAmount);

        // Check the remaining amount
        assertEq(SuccinctStaking(STAKING).maxDispense(), expectedMax - largeDispenseAmount);

        // Can still dispense the remainder
        deal(PROVE, STAKING, expectedMax - largeDispenseAmount);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(expectedMax - largeDispenseAmount);

        // Available should now be 0
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);
    }

    // Dispense using type(uint256).max should dispense exactly maxDispense()
    function test_Dispense_WhenMaxUint() public {
        // Stake some amount so the contract has state for dispensing
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // Advance time so that some dispenseable amount accumulates
        uint256 waitTime = 2 days;
        skip(waitTime);

        // Compute how much should be available
        uint256 available = SuccinctStaking(STAKING).maxDispense();
        assertEq(available, waitTime * DISPENSE_RATE);

        // Remember I_PROVE’s existing PROVE balance (from staking)
        uint256 oldVaultBalance = IERC20(PROVE).balanceOf(I_PROVE);

        // Fund the staking contract with exactly 'available' PROVE tokens
        deal(PROVE, STAKING, available);

        // Owner calls dispense with max uint256 sentinel
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(type(uint256).max);

        // After dispensing, maxDispense() should be zero
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);

        // The I_PROVE vault’s new balance should equal old + available
        uint256 newVaultBalance = IERC20(PROVE).balanceOf(I_PROVE);
        assertEq(newVaultBalance, oldVaultBalance + available);
    }

    // Dispense using type(uint256).max when there is no stake should still work
    function test_Dispense_WhenMaxUintNoStake() public {
        // Advance time so that dispenseable amount accumulates
        uint256 waitTime = 1 days;
        skip(waitTime);

        // Compute available (even with no stake, time passes)
        uint256 available = SuccinctStaking(STAKING).maxDispense();
        assertEq(available, waitTime * DISPENSE_RATE);

        // Fund the staking contract
        deal(PROVE, STAKING, available);

        // Owner calls dispense with max uint256 sentinel
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(type(uint256).max);

        // I_PROVE vault should have received exactly 'available' PROVE
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), available);

        // After dispensing, there should be no more available
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);
    }

    // Reverts when the staking contract doesn't have enough $PROVE. Operationally,
    // the owner should ensure that enough $PROVE is owned before dispensing.
    function test_RevertDispense_WhenNotEnoughPROVE() public {
        uint256 proveBalance = IERC20(PROVE).balanceOf(STAKING);
        uint256 dispenseAmount = proveBalance + 1;

        // Wait so that the available dispense goes up
        _waitRequiredDispenseTime(dispenseAmount);

        // Try to dispense more than the available amount
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(STAKING),
                proveBalance,
                dispenseAmount
            )
        );
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(dispenseAmount);
    }

    // Test that owner can update dispense rate
    function test_SetDispenseRate_WhenValid() public {
        uint256 newRate = DISPENSE_RATE * 2;

        // Non-owner cannot set rate
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        SuccinctStaking(STAKING).updateDispenseRate(newRate);

        // Owner can set rate
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(newRate);

        // Wait some time
        uint256 waitTime = 1 days;
        skip(waitTime);

        // Check max dispense with new rate
        uint256 maxAmount = SuccinctStaking(STAKING).maxDispense();
        assertEq(maxAmount, waitTime * newRate);
    }

    function test_Revert_WhenSetDispenseRate_WhenNotOwner() public {
        uint256 newRate = 0;
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        SuccinctStaking(STAKING).updateDispenseRate(newRate);
    }

    function testFuzz_Dispense_WhenValid(uint256 _dispenseAmount) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        // Use a more reasonable upper bound for testing
        uint256 maxDispenseAmount = 1_000_000e18; // 1M tokens
        uint256 dispenseAmount = bound(_dispenseAmount, 1000, maxDispenseAmount);

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // Dispense
        _dispense(dispenseAmount);

        // Verify rewards were distributed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        uint256 expectedStakedAfterDispense = stakeAmount + dispenseAmount;
        assertApproxEqAbs(
            SuccinctStaking(STAKING).staked(STAKER_1), expectedStakedAfterDispense, 10
        );
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount + dispenseAmount);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertApproxEqAbs(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount + dispenseAmount, 10);
        assertApproxEqAbs(IERC20(PROVE).balanceOf(I_PROVE), 0, 10);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
    }

    function testFuzz_Dispense_MultipleStakers(
        uint256[3] memory _stakeAmounts,
        uint256 _dispenseAmount
    ) public {
        address[3] memory stakers = [STAKER_1, STAKER_2, makeAddr("STAKER_3")];
        uint256 totalStaked = 0;

        // Setup stakers
        for (uint256 i = 0; i < stakers.length; i++) {
            _stakeAmounts[i] = bound(_stakeAmounts[i], MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT / 3);
            deal(PROVE, stakers[i], _stakeAmounts[i]);
            _stake(stakers[i], ALICE_PROVER, _stakeAmounts[i]);
            totalStaked += _stakeAmounts[i];
        }

        uint256 dispenseAmount = bound(_dispenseAmount, 1000, 1_000_000e18);

        // Dispense
        _dispense(dispenseAmount);

        // Verify each staker's balance increased proportionally
        for (uint256 i = 0; i < stakers.length; i++) {
            uint256 expectedStaked =
                _stakeAmounts[i] + (_stakeAmounts[i] * dispenseAmount / totalStaked);
            // Dynamic tolerance: 0.001% of expected value or 10, whichever is larger
            uint256 tolerance = expectedStaked / 100000 > 10 ? expectedStaked / 100000 : 10;
            assertApproxEqAbs(
                SuccinctStaking(STAKING).staked(stakers[i]),
                expectedStaked,
                tolerance,
                "Staker should receive proportional dispense"
            );
        }
    }

    function testFuzz_Dispense_MultipleProvers(
        uint256[2] memory _stakeAmounts,
        uint256 _dispenseAmount
    ) public {
        uint256 stakeAmount1 = bound(_stakeAmounts[0], MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT / 2);
        uint256 stakeAmount2 = bound(_stakeAmounts[1], MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT / 2);
        uint256 dispenseAmount = bound(_dispenseAmount, 1000, 1_000_000e18);

        // Stake to different provers
        _stake(STAKER_1, ALICE_PROVER, stakeAmount1);
        deal(PROVE, STAKER_2, stakeAmount2);
        _stake(STAKER_2, BOB_PROVER, stakeAmount2);

        // Dispense affects all provers
        _dispense(dispenseAmount);

        // Total stake across all provers
        uint256 totalStaked = stakeAmount1 + stakeAmount2;

        // Verify dispense distributed proportionally
        uint256 expectedStaked1 = stakeAmount1 + (stakeAmount1 * dispenseAmount / totalStaked);
        uint256 expectedStaked2 = stakeAmount2 + (stakeAmount2 * dispenseAmount / totalStaked);

        // Dynamic tolerance: 0.001% of expected value or 10, whichever is larger
        uint256 tolerance1 = expectedStaked1 / 100000 > 10 ? expectedStaked1 / 100000 : 10;
        uint256 tolerance2 = expectedStaked2 / 100000 > 10 ? expectedStaked2 / 100000 : 10;

        assertApproxEqAbs(SuccinctStaking(STAKING).staked(STAKER_1), expectedStaked1, tolerance1);
        assertApproxEqAbs(SuccinctStaking(STAKING).staked(STAKER_2), expectedStaked2, tolerance2);
    }

    function testFuzz_Dispense_WithUnstakeRequests(uint256 _dispenseAmount, uint256 _unstakePercent)
        public
    {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        // Bound dispense amount to what can accumulate in 30 days
        uint256 maxDispenseIn30Days = DISPENSE_RATE * 30 days;
        uint256 dispenseAmount = bound(_dispenseAmount, 1000, maxDispenseIn30Days);
        uint256 unstakePercent = bound(_unstakePercent, 10, 90);
        uint256 unstakeAmount = (stakeAmount * unstakePercent) / 100;

        // Stake
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request unstake
        _requestUnstake(STAKER_1, unstakeAmount);

        // Dispense while unstake is pending
        _dispense(dispenseAmount);

        // Complete unstake
        skip(UNSTAKE_PERIOD);
        uint256 receivedAmount = _finishUnstake(STAKER_1);

        // Unstaked amount should not include dispense rewards
        // The snapshot was taken before dispense, so it shouldn't include rewards
        // But ERC4626 rounding can cause small differences proportional to the amount
        uint256 unstakeTolerance = unstakeAmount / 100000 > 10 ? unstakeAmount / 100000 : 10;
        assertApproxEqAbs(receivedAmount, unstakeAmount, unstakeTolerance);

        // Verify the remaining stake got the dispense rewards
        // Since this is the only staker, they get all the dispense rewards on their remaining stake
        uint256 actualRemaining = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 expectedRemaining = stakeAmount - unstakeAmount + dispenseAmount;
        uint256 remainingTolerance =
            expectedRemaining / 100000 > 10 ? expectedRemaining / 100000 : 10;
        assertApproxEqAbs(actualRemaining, expectedRemaining, remainingTolerance);
    }

    function testFuzz_Dispense_RateChanges(
        uint256 _initialRate,
        uint256 _newRate,
        uint256 _waitTime
    ) public {
        uint256 initialRate = bound(_initialRate, 1, DISPENSE_RATE * 2);
        uint256 newRate = bound(_newRate, 1, DISPENSE_RATE * 2);
        uint256 waitTime = bound(_waitTime, 1 days, 30 days);

        // Stake
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // Set initial rate
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(initialRate);

        // Wait and dispense
        skip(waitTime);
        uint256 firstAvailable = SuccinctStaking(STAKING).maxDispense();
        uint256 firstDispense = firstAvailable / 2;
        deal(PROVE, STAKING, firstDispense);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(firstDispense);

        // Change rate
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(newRate);

        // Wait again
        skip(waitTime);
        uint256 secondAvailable = SuccinctStaking(STAKING).maxDispense();

        // Verify rate change took effect
        // When we dispensed, lastDispenseTimestamp advanced by timeConsumed
        uint256 timeConsumed = (firstDispense + initialRate - 1) / initialRate;

        // After rate change and second wait, available amount is calculated from
        // the time elapsed since lastDispenseTimestamp with the new rate
        // Time elapsed = waitTime + (waitTime - timeConsumed) = 2 * waitTime - timeConsumed
        uint256 expectedSecondAvailable = (2 * waitTime - timeConsumed) * newRate;
        assertEq(secondAvailable, expectedSecondAvailable);
    }
}
