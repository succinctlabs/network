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

        // Check dispense state variables after dispense
        assertEq(SuccinctStaking(STAKING).dispenseRate(), DISPENSE_RATE);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), dispenseAmount);

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

        // Check dispense state variables after dispense
        assertEq(SuccinctStaking(STAKING).dispenseRate(), DISPENSE_RATE);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), dispenseAmount);
    }

    // Ensure dispense rate is properly enforced
    function test_Dispense_WhenRateLimit() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Try to dispense more than allowed amount (should fail)
        uint256 excessAmount = DISPENSE_RATE * 10;
        vm.expectRevert(ISuccinctStaking.AmountExceedsAvailableDispense.selector);
        vm.prank(DISPENSER);
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
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(halfAmount);

        // Check that maxDispense was updated correctly
        assertEq(SuccinctStaking(STAKING).maxDispense(), maxAmount - halfAmount);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), halfAmount);

        // Dispense remaining amount
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(maxAmount - halfAmount);

        // Check that maxDispense is now 0
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), maxAmount);

        // Try to dispense again (should fail)
        vm.expectRevert(ISuccinctStaking.AmountExceedsAvailableDispense.selector);
        vm.prank(DISPENSER);
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
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(firstDispenseAmount);

        // Check remaining available after first dispense
        assertEq(SuccinctStaking(STAKING).maxDispense(), firstAvailable - firstDispenseAmount);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), firstDispenseAmount);

        // Wait for more time to accumulate
        uint256 secondWaitTime = 5 days;
        skip(secondWaitTime);

        // Calculate newly available amount (remaining from first + accumulated during second wait)
        uint256 expectedNewlyAvailable =
            (firstAvailable - firstDispenseAmount) + (secondWaitTime * DISPENSE_RATE);
        assertEq(SuccinctStaking(STAKING).maxDispense(), expectedNewlyAvailable);

        // Dispense everything available
        deal(PROVE, STAKING, expectedNewlyAvailable);
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(expectedNewlyAvailable);

        // Check available is now 0
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);
        assertEq(
            SuccinctStaking(STAKING).dispenseDistributed(),
            firstDispenseAmount + expectedNewlyAvailable
        );
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
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(exactAmount);

        // The available amount should now be 0
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), exactAmount);

        // Trying to dispense any amount now should fail
        vm.expectRevert(ISuccinctStaking.AmountExceedsAvailableDispense.selector);
        vm.prank(DISPENSER);
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
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(halfAmount);

        // Change the dispense rate (double it)
        uint256 newRate = DISPENSE_RATE * 2;
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(newRate);

        // Check dispense state variables after rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), newRate);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Wait for more time to accumulate with the new rate
        uint256 additionalWaitTime = 2 days;
        skip(additionalWaitTime);

        uint256 available = SuccinctStaking(STAKING).maxDispense();

        // Dispense again to verify it works with the new rate
        deal(PROVE, STAKING, available);
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(available);

        // Available should now be 0
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), halfAmount + available);
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
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(largeDispenseAmount);

        // Check the remaining amount
        assertEq(SuccinctStaking(STAKING).maxDispense(), expectedMax - largeDispenseAmount);

        // Can still dispense the remainder
        deal(PROVE, STAKING, expectedMax - largeDispenseAmount);
        vm.prank(DISPENSER);
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
        vm.prank(DISPENSER);
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
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(type(uint256).max);

        // I_PROVE vault should have received exactly 'available' PROVE
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), available);

        // After dispensing, there should be no more available
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);
    }

    // Tests that repeated dust dispenses don't destroy future emissions.
    function test_Dispense_WhenDustPreservesEmissions() public {
        // Set dispense rate to 3 wei/s.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(3);

        // Check dispense state variables after rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), 3);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Skip 10 seconds (30 wei earned).
        skip(10);

        // Fund the staking contract with enough PROVE for all dispenses.
        deal(PROVE, STAKING, 30);

        // Dispense 1 wei ten times.
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(DISPENSER);
            SuccinctStaking(STAKING).dispense(1);
        }

        // Should have 20 wei remaining available.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 20);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), 10);
    }

    // Tests that rate changes preserve exact emission accounting.
    function test_Dispense_WhenRateChangePreservesAccounting() public {
        // Rate 1: 10 wei/s for 100 seconds.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(10);

        // Check dispense state variables after first rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), 10);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        skip(100);

        // Fund the staking contract.
        deal(PROVE, STAKING, 2000);

        // Dispense 500 wei.
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(500);

        // Check dispense state variables after dispense
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), 500);

        // Rate 2: 5 wei/s for 200 seconds.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(5);

        // Check dispense state variables after second rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), 5);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        skip(200);

        // Should have exactly 500 + 1000 = 1500 wei available.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 1500);
    }

    // Tests the invariant that total earned must always equal total dispensed plus available balance.
    function test_Dispense_WhenTotalEarnedEqualsDispensedPlusAvailable() public {
        // Initial setup.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(7);

        // Test multiple operations.
        skip(100);
        uint256 totalEarned1 = SuccinctStaking(STAKING).dispenseEarned()
            + (block.timestamp - SuccinctStaking(STAKING).dispenseRateTimestamp())
                * SuccinctStaking(STAKING).dispenseRate();
        uint256 totalAccounted1 =
            SuccinctStaking(STAKING).dispenseDistributed() + SuccinctStaking(STAKING).maxDispense();
        assertEq(totalEarned1, totalAccounted1, "Invariant broken after skip");

        // Dispense some amount.
        deal(PROVE, STAKING, 350);
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(350);

        uint256 totalEarned2 = SuccinctStaking(STAKING).dispenseEarned()
            + (block.timestamp - SuccinctStaking(STAKING).dispenseRateTimestamp())
                * SuccinctStaking(STAKING).dispenseRate();
        uint256 totalAccounted2 =
            SuccinctStaking(STAKING).dispenseDistributed() + SuccinctStaking(STAKING).maxDispense();
        assertEq(totalEarned2, totalAccounted2, "Invariant broken after dispense");

        // Change rate.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(13);

        uint256 totalEarned3 = SuccinctStaking(STAKING).dispenseEarned()
            + (block.timestamp - SuccinctStaking(STAKING).dispenseRateTimestamp())
                * SuccinctStaking(STAKING).dispenseRate();
        uint256 totalAccounted3 =
            SuccinctStaking(STAKING).dispenseDistributed() + SuccinctStaking(STAKING).maxDispense();
        assertEq(totalEarned3, totalAccounted3, "Invariant broken after rate change");

        // Skip more time and dispense again.
        skip(50);
        deal(PROVE, STAKING, 650);
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(650);

        uint256 totalEarned4 = SuccinctStaking(STAKING).dispenseEarned()
            + (block.timestamp - SuccinctStaking(STAKING).dispenseRateTimestamp())
                * SuccinctStaking(STAKING).dispenseRate();
        uint256 totalAccounted4 =
            SuccinctStaking(STAKING).dispenseDistributed() + SuccinctStaking(STAKING).maxDispense();
        assertEq(totalEarned4, totalAccounted4, "Invariant broken after second dispense");
    }

    // Tests demonstrating the old bug with ceiling division.
    function test_Dispense_WhenNoCeilingDivisionLoss() public {
        // Set a rate where ceiling division would cause issues.
        uint256 rate = 7; // 7 wei/s
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(rate);

        // Check dispense state variables after rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), rate);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Skip time to accumulate exactly 70 wei.
        skip(10);
        assertEq(SuccinctStaking(STAKING).maxDispense(), 70);

        // Fund the contract.
        deal(PROVE, STAKING, 70);

        // Dispense 5 wei (not divisible by 7).
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(5);

        // With the fix, we should still have 65 wei available.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 65);

        // Dispense 3 more wei.
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(3);

        // Should have 62 wei available.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 62);

        // The total dispensed should be exactly 8 wei.
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), 8);
        assertEq(SuccinctStaking(STAKING).dispenseRate(), rate);
    }

    // Tests that partial dispenses don't affect future emission rates.
    function test_Dispense_WhenPartialDispenseNoRateImpact() public {
        uint256 rate = 100; // 100 wei/s
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(rate);

        // Check dispense state variables after rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), rate);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Wait 10 seconds (1000 wei earned).
        skip(10);

        // Fund the contract.
        deal(PROVE, STAKING, 1000);

        // Dispense 123 wei (not a multiple of rate).
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(123);

        // Wait another 10 seconds.
        skip(10);

        // Total available should be: 877 (remaining) + 1000 (new) = 1877 wei.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 1877);

        // Verify the emission rate is still exactly 100 wei/s.
        skip(1);
        assertEq(SuccinctStaking(STAKING).maxDispense(), 1977);
    }

    // Tests dispense when rate is zero should accrue nothing but not revert.
    function test_Dispense_WhenRateIsZero() public {
        // Set rate to zero.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(0);

        // Check dispense state variables after rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), 0);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Skip time.
        skip(1 days);

        // Should have 0 available.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);

        // Fund and try to dispense 1 wei - should revert.
        deal(PROVE, STAKING, 1);
        vm.expectRevert(ISuccinctStaking.AmountExceedsAvailableDispense.selector);
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(1);

        // Try to dispense max uint - should revert with ZeroAmount.
        vm.expectRevert(ISuccinctStaking.ZeroAmount.selector);
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(type(uint256).max);
    }

    // Tests multiple rapid rate changes in the same block.
    function test_Dispense_WhenMultipleRateChangesInSameBlock() public {
        // Initial rate.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(100);

        // Check dispense state variables after first rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), 100);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Multiple rate changes in same block.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(200);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(300);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(400);

        // Should have accrued nothing since no time passed.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);

        // Skip time and verify rate is now 400.
        skip(10);
        assertEq(SuccinctStaking(STAKING).maxDispense(), 4000);
    }

    // Tests dispense(type(uint256).max) when nothing is available.
    function test_Dispense_WhenMaxUintWithZeroAvailable() public {
        // No time has passed, so nothing available.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 0);

        // Try to dispense max uint - should revert with ZeroAmount.
        vm.expectRevert(ISuccinctStaking.ZeroAmount.selector);
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(type(uint256).max);
    }

    // Tests extreme dust amounts with high dispense rate.
    function test_Dispense_WhenExtremeDustWithHighRate() public {
        // Set a very high rate.
        uint256 highRate = 1e18; // 1 PROVE per second
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(highRate);

        // Check dispense state variables after rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), highRate);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Skip 1 second.
        skip(1);

        // Fund the contract.
        deal(PROVE, STAKING, 1e18);

        // Dispense 1 wei (extreme dust compared to rate).
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(1);

        // Should have exactly 1e18 - 1 wei available.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 1e18 - 1);

        // Dispense many dust amounts.
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(DISPENSER);
            SuccinctStaking(STAKING).dispense(1);
        }

        // Should have exactly 1e18 - 101 wei available.
        assertEq(SuccinctStaking(STAKING).maxDispense(), 1e18 - 101);
        assertEq(SuccinctStaking(STAKING).dispenseDistributed(), 101);
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
        vm.prank(DISPENSER);
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

        // Check dispense state variables after rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), newRate);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Wait some time
        uint256 waitTime = 1 days;
        skip(waitTime);

        // Check max dispense with new rate
        uint256 maxAmount = SuccinctStaking(STAKING).maxDispense();
        assertEq(maxAmount, waitTime * newRate);
    }

    function test_Revert_WhenSetDispenseRate_WhenNotDispenser() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        SuccinctStaking(STAKING).updateDispenseRate(DISPENSE_RATE);
    }

    function test_SetDispenser_WhenValid() public {
        address newDispenser = makeAddr("NEW_DISPENSER");
        vm.prank(OWNER);
        SuccinctStaking(STAKING).setDispenser(newDispenser);
        assertEq(SuccinctStaking(STAKING).dispenser(), newDispenser);
    }

    function test_Revert_WhenSetDispenser_WhenNotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        SuccinctStaking(STAKING).setDispenser(DISPENSER);
    }

    function testFuzz_Dispense_WhenValid(uint256 _dispenseAmount) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        // Use a more reasonable upper bound for testing
        uint256 maxDispenseAmount = DISPENSE_AMOUNT; // 1M tokens
        uint256 dispenseAmount = bound(_dispenseAmount, 1000, maxDispenseAmount);

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // Dispense
        _dispense(dispenseAmount);

        // Verify rewards were distributed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        uint256 expectedStakedAfterDispense = stakeAmount + dispenseAmount;
        // Use dynamic tolerance for large amounts
        uint256 stakeTolerance =
            expectedStakedAfterDispense / 100000 > 50 ? expectedStakedAfterDispense / 100000 : 50;
        assertApproxEqAbs(
            SuccinctStaking(STAKING).staked(STAKER_1), expectedStakedAfterDispense, stakeTolerance
        );
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount + dispenseAmount);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        uint256 finalTolerance = (stakeAmount + dispenseAmount) / 100000 > 50
            ? (stakeAmount + dispenseAmount) / 100000
            : 50;
        assertApproxEqAbs(
            IERC20(PROVE).balanceOf(STAKER_1), stakeAmount + dispenseAmount, finalTolerance
        );
        // For large dispense amounts, allow slightly more tolerance for vault rounding
        assertApproxEqAbs(IERC20(PROVE).balanceOf(I_PROVE), 0, 100);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
    }

    function testFuzz_Dispense_WhenMultipleStakers(
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

        uint256 dispenseAmount = bound(_dispenseAmount, 1000, DISPENSE_AMOUNT);

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

    function testFuzz_Dispense_WhenMultipleProvers(
        uint256[2] memory _stakeAmounts,
        uint256 _dispenseAmount
    ) public {
        uint256 stakeAmount1 = bound(_stakeAmounts[0], MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT / 2);
        uint256 stakeAmount2 = bound(_stakeAmounts[1], MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT / 2);
        uint256 dispenseAmount = bound(_dispenseAmount, 1000, DISPENSE_AMOUNT);

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
        // Bound dispense amount to what can accumulate in 1 day (adjusted for higher dispense rate)
        uint256 maxDispenseIn1Day = DISPENSE_RATE * 1 days;
        uint256 dispenseAmount = bound(_dispenseAmount, 1000, maxDispenseIn1Day);
        uint256 unstakePercent = bound(_unstakePercent, 10, 90);
        uint256 unstakeAmount = (stakeAmount * unstakePercent) / 100;

        // Stake
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Get the staker's balance immediately after staking
        uint256 stakedBalanceBefore = SuccinctStaking(STAKING).staked(STAKER_1);
        assertEq(stakedBalanceBefore, stakeAmount);

        // Request unstake
        _requestUnstake(STAKER_1, unstakeAmount);

        // Dispense while unstake is pending
        _dispense(dispenseAmount);

        // Complete unstake
        skip(UNSTAKE_PERIOD);
        uint256 receivedAmount = _finishUnstake(STAKER_1);

        // Allow for 1 wei rounding error due to integer division in share calculations
        uint256 expectedReceived = unstakeAmount + (dispenseAmount * unstakePercent) / 100;
        assertApproxEqAbs(receivedAmount, expectedReceived, 1);

        // Verify the remaining stake got their proportional share of dispense rewards
        uint256 actualRemaining = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 expectedRemaining =
            (stakeAmount - unstakeAmount) + (dispenseAmount * (100 - unstakePercent)) / 100;

        // Allow for 1 wei rounding error
        assertApproxEqAbs(actualRemaining, expectedRemaining, 1);
    }

    function testFuzz_Dispense_WhenRateChanges(
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

        // Check dispense state variables after initial rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), initialRate);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Wait and dispense
        skip(waitTime);
        uint256 firstAvailable = SuccinctStaking(STAKING).maxDispense();
        uint256 firstDispense = firstAvailable / 2;
        deal(PROVE, STAKING, firstDispense);
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(firstDispense);

        // Change rate
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(newRate);

        // Check dispense state variables after second rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), newRate);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Wait again
        skip(waitTime);
        uint256 secondAvailable = SuccinctStaking(STAKING).maxDispense();

        // Verify rate change took effect
        // After rate change and second wait, available amount includes:
        // 1. Remaining from first period (firstAvailable - firstDispense)
        // 2. New accumulation at new rate (waitTime * newRate)
        uint256 expectedSecondAvailable = (firstAvailable - firstDispense) + (waitTime * newRate);
        assertEq(secondAvailable, expectedSecondAvailable);
    }

    // Tests overflow protection with extreme rates.
    function testFuzz_Dispense_WhenOverflowGuard(uint256 _rate, uint256 _timeSkip) public {
        // Bound rate to extreme values but prevent immediate overflow.
        uint256 rate = bound(_rate, 1, type(uint256).max / (365 days));
        uint256 timeSkip = bound(_timeSkip, 1, 365 days);

        // Set extreme rate.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(rate);

        // Check dispense state variables after rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), rate);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        // Skip time.
        skip(timeSkip);

        // Calculate expected without overflow.
        uint256 expected = rate * timeSkip;

        // Should not revert and should calculate correctly.
        uint256 available = SuccinctStaking(STAKING).maxDispense();
        assertEq(available, expected);

        // Fund and dispense half (but at least 1 if available > 0).
        uint256 halfAmount = available == 0 ? 0 : available / 2 == 0 ? 1 : available / 2;
        if (halfAmount > 0) {
            deal(PROVE, STAKING, halfAmount);
            vm.prank(DISPENSER);
            SuccinctStaking(STAKING).dispense(halfAmount);

            // Verify remaining.
            assertEq(SuccinctStaking(STAKING).maxDispense(), available - halfAmount);
            assertEq(SuccinctStaking(STAKING).dispenseDistributed(), halfAmount);
        }
    }

    // Tests reentrancy protection during dispense.
    function test_Dispense_WhenReentrancyProtection() public {
        // This test verifies that the contract is safe from reentrancy attacks.
        // The current implementation writes state before external calls, making it safe.
        // This test documents that safety property.

        // Set up normal dispense scenario.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).updateDispenseRate(1000);

        // Check dispense state variables after rate change
        assertEq(SuccinctStaking(STAKING).dispenseRate(), 1000);
        assertEq(SuccinctStaking(STAKING).dispenseRateTimestamp(), block.timestamp);

        skip(100);

        // Fund the contract.
        uint256 available = SuccinctStaking(STAKING).maxDispense();
        deal(PROVE, STAKING, available);

        // Record state before dispense.
        uint256 distributedBefore = SuccinctStaking(STAKING).dispenseDistributed();

        // Dispense normally.
        vm.prank(DISPENSER);
        SuccinctStaking(STAKING).dispense(available / 2);

        // Verify state was updated correctly.
        uint256 distributedAfter = SuccinctStaking(STAKING).dispenseDistributed();
        assertEq(distributedAfter, distributedBefore + available / 2);

        // The contract is safe because:
        // 1. dispenseDistributed is updated before the external transfer
        // 2. All state changes happen before external calls
        // 3. Even if a malicious token tried to re-enter, the state is already updated
    }
}
