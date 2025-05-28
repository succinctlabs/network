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
        // balanceOf increases because there is more PROVE underlying per DST-PROVE
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        // staked increases because the redemption value is higher
        uint256 expectedStakedAfterDispense = stakeAmount + dispenseAmount - 1; // Allow for rounding
        assertGe(SuccinctStaking(STAKING).staked(STAKER_1), expectedStakedAfterDispense - 1);
        assertLe(SuccinctStaking(STAKING).staked(STAKER_1), expectedStakedAfterDispense + 1);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount + dispenseAmount);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);

        // Note: due to rounding, 1 $PROVE is left over in I_PROVE.
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount + dispenseAmount - 1);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 1);
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
    function test_Dispense_RateLimit() public {
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

        // Check that maxDispense is now 0 (or close to it due to slight timing differences)
        assertLe(SuccinctStaking(STAKING).maxDispense(), 1);

        // Try to dispense again (should fail)
        vm.expectRevert(ISuccinctStaking.AmountExceedsAvailableDispense.selector);
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(1);
    }

    // Consecutive dispenses with waiting periods
    function test_Dispense_ConsecutiveWithWaiting() public {
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

        // Check available is now 0 (or very close due to rounding)
        assertLe(SuccinctStaking(STAKING).maxDispense(), 1);
    }

    // Dispensing exactly at the limit
    function test_Dispense_ExactLimit() public {
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
    function test_Dispense_RateChangeEffects() public {
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

        // Available should now be 0 or very close
        assertLe(SuccinctStaking(STAKING).maxDispense(), 1);
    }

    // Dispense calculation with very large time periods
    function test_Dispense_VeryLargeTimePeriod() public {
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
}
