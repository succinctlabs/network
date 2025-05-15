// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract SuccinctStakingUnstakeTests is SuccinctStakingTest {
    function test_Unstake_WhenValid() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Sanity check
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, 0), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0);

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Check balances after stake
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        // assertEq(SuccinctStaking(STAKING).claimable(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount);

        // Step 1: Submit unstake request
        _requestUnstake(STAKER_1, stakeAmount);

        // Nothing should have changed
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        // assertEq(SuccinctStaking(STAKING).claimable(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount);

        // Step 2: Wait for unstake period to pass and claim
        skip(UNSTAKE_PERIOD);
        _finishUnstake(STAKER_1);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        // assertEq(SuccinctStaking(STAKING).claimable(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, 0), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0);
    }

    // 2 stakers, 1 prover - with a reward being sent to the prover
    function test_Unstake_WhenTwoStakersOneProverReward() public {
        uint256 stakeAmount1 = STAKER_PROVE_AMOUNT / 2;
        uint256 stakeAmount2 = STAKER_PROVE_AMOUNT / 4;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Both stakers deposit to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount1);
        _permitAndStake(STAKER_2, STAKER_2_PK, ALICE_PROVER, stakeAmount2);

        // Record initial staked amounts
        uint256 initialStaked1 = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 initialStaked2 = SuccinctStaking(STAKING).staked(STAKER_2);

        // Verify initial state after staking
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount1);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), stakeAmount2);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount1 + stakeAmount2);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT - stakeAmount1);
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), STAKER_PROVE_AMOUNT - stakeAmount2);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount1 + stakeAmount2);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount1 + stakeAmount2);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount1);
        assertEq(IERC20(STAKING).balanceOf(STAKER_2), stakeAmount2);

        // Reward to Alice prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Calculate expected rewards (proportional to stake)
        uint256 expectedReward1 = (rewardAmount * stakeAmount1) / (stakeAmount1 + stakeAmount2);
        uint256 expectedReward2 = (rewardAmount * stakeAmount2) / (stakeAmount1 + stakeAmount2);

        // Verify staked amount increased for both stakers
        uint256 stakedAfterReward1 = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 stakedAfterReward2 = SuccinctStaking(STAKING).staked(STAKER_2);
        assertEq(stakedAfterReward1, initialStaked1 + expectedReward1 - 1); // Account for rounding
        assertEq(stakedAfterReward2, initialStaked2 + expectedReward2 - 1); // No rounding issue here

        // Both stakers unstake and claim
        _completeUnstake(STAKER_1, stakeAmount1);
        _completeUnstake(STAKER_2, stakeAmount2);

        // Verify final state after unstaking
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 2); // There is 1 left over for each staker

        // Both stakers should get their original stake plus proportional rewards
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1),
            STAKER_PROVE_AMOUNT - stakeAmount1 + stakeAmount1 + expectedReward1 - 1
        ); // Account for rounding
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_2),
            STAKER_PROVE_AMOUNT - stakeAmount2 + stakeAmount2 + expectedReward2
        ); // No rounding issue here
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_2), 0);
    }

    function test_RevertUnstake_WhenZeroAmount() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = 0;

        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.ZeroAmount.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(unstakeAmount);
    }

    // 1 staker, 2 provers, - stake is only send to the prover who did not get a reward
    function test_Unstake_WhenOneStakerTwoProversRewardNonDelegated() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT / 2;

        // Staker 1 deposits to Alice prover and Bob prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);
        // Not related to this test: Bob prover needs to have some stake to be able to get rewards
        _permitAndStake(STAKER_2, STAKER_2_PK, BOB_PROVER, stakeAmount);

        // Reward to Bob's prover (the one STAKER_1 did NOT delegate to)
        MockVApp(VAPP).processReward(BOB_PROVER, rewardAmount);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify staker only gets original stake (no rewards)
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
        assertEq(IERC20(BOB_PROVER).balanceOf(STAKER_1), 0);
    }

    // 2 stakers, 2 provers - dispense only
    function test_Unstake_WhenTwoStakersTwoProversDispenseOnly() public {
        uint256 stakeAmount1 = STAKER_PROVE_AMOUNT / 2;
        uint256 stakeAmount2 = STAKER_PROVE_AMOUNT / 4;
        uint256 dispenseAmount = STAKER_PROVE_AMOUNT;

        // Each staker deposits to a different prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount1);
        _permitAndStake(STAKER_2, STAKER_2_PK, BOB_PROVER, stakeAmount2);

        // Wait for enough time to allow the dispense amount
        uint256 requiredTime = dispenseAmount / DISPENSE_RATE + 1;
        skip(requiredTime);

        // Dispense rewards to all stakers
        vm.prank(OWNER);
        SuccinctStaking(STAKING).dispense(dispenseAmount);

        // Complete unstake process for both stakers
        _completeUnstake(STAKER_1, stakeAmount1);
        _completeUnstake(STAKER_2, stakeAmount2);

        // Calculate expected rewards (proportional to stake)
        uint256 expectedDispense1 = (dispenseAmount * stakeAmount1) / (stakeAmount1 + stakeAmount2);
        uint256 expectedDispense2 = (dispenseAmount * stakeAmount2) / (stakeAmount1 + stakeAmount2);

        // Verify final balances with dispense. Note: off-by-one is expected due to rounding.
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT + expectedDispense1 - 1);
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), STAKER_PROVE_AMOUNT + expectedDispense2);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
        assertEq(IERC20(BOB_PROVER).balanceOf(STAKER_2), 0);
    }

    // Test claiming before the unstake period has passed
    function test_Unstake_WhenEarlyAttempt() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 partialUnstakePeriod = UNSTAKE_PERIOD - 1 days;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Unstake from Alice prover
        _requestUnstake(STAKER_1, stakeAmount);

        // Wait for less than the unstake period
        skip(partialUnstakePeriod);

        // Try to claim unstaked tokens early - should not receive tokens yet
        _finishUnstake(STAKER_1);

        // Verify that tokens are still not received
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);

        // Wait for the rest of the unstake period
        skip(1 days);

        // Claim unstaked tokens after the full period
        _finishUnstake(STAKER_1);

        // Now tokens should be received
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount);
    }

    // Test multiple unstakes in the queue
    function test_Unstake_WhenMultipleUnstakes() public {
        uint256 firstStakeAmount = 40;
        uint256 secondStakeAmount = 60;
        uint256 halfUnstakePeriod = UNSTAKE_PERIOD / 2;

        // Staker 1 deposits twice to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, firstStakeAmount);
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, secondStakeAmount);

        // Verify the stake was successful
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), firstStakeAmount + secondStakeAmount);

        // First unstake
        _requestUnstake(STAKER_1, firstStakeAmount);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), firstStakeAmount);

        // Second unstake with a delay
        skip(halfUnstakePeriod); // part way through the unstaking period
        _requestUnstake(STAKER_1, secondStakeAmount);
        assertEq(
            SuccinctStaking(STAKING).unstakePending(STAKER_1), firstStakeAmount + secondStakeAmount
        );

        // Wait until only the first unstake should be claimable
        skip(UNSTAKE_PERIOD - halfUnstakePeriod);

        // Claim the first unstake
        _finishUnstake(STAKER_1);

        // Verify first unstake is claimed but second isn't yet
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), secondStakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), firstStakeAmount);

        // Wait for the second unstake to be claimable
        skip(halfUnstakePeriod);

        // Claim the second unstake
        _finishUnstake(STAKER_1);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);

        // Verify both unstakes are now claimed
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), firstStakeAmount + secondStakeAmount);
    }

    // Test unstake queue with rewards
    function test_Unstake_WhenMultipleRewards() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = 50;
        uint256 totalRewards = rewardAmount * 2;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Record initial staked amount
        uint256 initialStaked = SuccinctStaking(STAKING).staked(STAKER_1);

        // Add rewards before unstaking
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Verify staked amount increased
        uint256 stakedAfterFirstReward = SuccinctStaking(STAKING).staked(STAKER_1);
        assertEq(stakedAfterFirstReward, initialStaked + rewardAmount - 1); // Account for rounding

        // Unstake from Alice prover
        _requestUnstake(STAKER_1, stakeAmount);

        // Add more rewards while tokens are in the unstake queue
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Skip to allow claiming
        skip(UNSTAKE_PERIOD);

        // Claim unstaked tokens
        uint256 claimedAmount = _finishUnstake(STAKER_1);

        // Verify the staker got their original stake + BOTH rewards
        assertEq(claimedAmount, stakeAmount + totalRewards - 1); // Account for rounding
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount + totalRewards - 1); // Account for rounding
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
    }

    function test_Unstake_WhenManySmallUnstakes() public {
        uint256 numUnstakes = 10;
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = STAKER_PROVE_AMOUNT / numUnstakes;

        // Stake some tokens to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Unstake some tokens from Alice prover, across multiple unstake calls
        for (uint256 i = 0; i < numUnstakes; i++) {
            _requestUnstake(STAKER_1, unstakeAmount);
        }

        // Wait for the unstake period to pass
        skip(UNSTAKE_PERIOD);

        // Claim the unstake
        _finishUnstake(STAKER_1);

        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
    }

    function test_Unstake_WhenManySmallStakesUnstakes() public {
        uint256 numStakes = 10;
        uint256 numUnstakes = 10;
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / numStakes;
        uint256 unstakeAmount = STAKER_PROVE_AMOUNT / numUnstakes;

        // Stake some tokens to Alice prover, across multiple stake calls
        for (uint256 i = 0; i < numStakes; i++) {
            _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);
        }

        // Unstake some tokens from Alice prover, across multiple unstake calls
        for (uint256 i = 0; i < numUnstakes; i++) {
            _requestUnstake(STAKER_1, unstakeAmount);
        }

        // Wait for the unstake period to pass
        skip(UNSTAKE_PERIOD);

        // Claim the unstake
        _finishUnstake(STAKER_1);

        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount * numStakes);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
    }

    function test_Unstake_WhenManySmallStakesUnstakesTimeBetween() public {
        uint256 numStakes = 10;
        uint256 numUnstakes = 10;
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / numStakes;
        uint256 unstakeAmount = STAKER_PROVE_AMOUNT / numUnstakes;
        uint256 timeBetweenStakes = 1 days;

        // Stake some tokens to Alice prover, across multiple stake calls
        for (uint256 i = 0; i < numStakes; i++) {
            _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

            skip(timeBetweenStakes);
        }

        // Unstake some tokens from Alice prover, across multiple unstake calls
        for (uint256 i = 0; i < numUnstakes; i++) {
            _requestUnstake(STAKER_1, unstakeAmount);

            skip(timeBetweenStakes);
        }

        // Wait for the unstake period to pass
        skip(UNSTAKE_PERIOD);

        // Claim the unstake
        _finishUnstake(STAKER_1);

        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount * numStakes);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
    }

    function test_RevertUnstake_WhenSomeoneElseCallsClaimUnstake() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = STAKER_PROVE_AMOUNT;

        // Stake some tokens to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Someone else should not be able to claim the unstake
        vm.expectRevert(ISuccinctStaking.NotStaked.selector);
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).finishUnstake();

        // Unstake some tokens from Alice prover
        _requestUnstake(STAKER_1, unstakeAmount);

        // Someone else should not be able to claim the unstake, even after unstake has been called
        vm.expectRevert(ISuccinctStaking.NotStaked.selector);
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).finishUnstake();
    }

    function test_RevertUnstake_WhenAmountExceedsBalance() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2; // Only stake half of the tokens
        uint256 unstakeAmount = STAKER_PROVE_AMOUNT; // Try to unstake more than staked

        // Stake some tokens to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Unstaking more than staked should revert.
        vm.expectRevert(ISuccinctStaking.InsufficientStakeBalance.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(unstakeAmount);
    }

    function test_RevertUnstake_WhenRequestUnstakeWhileProverHasSlashRequest() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 slashAmount = STAKER_PROVE_AMOUNT / 2;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Request slash for Alice prover tokens
        MockVApp(VAPP).processSlash(ALICE_PROVER, slashAmount);

        // Attempt to unstake while there's a pending slash request - should revert
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.ProverHasSlashRequest.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(stakeAmount);
    }

    function test_RevertUnstake_WhenFinishUnstakeWhileProverHasSlashRequest() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 slashAmount = STAKER_PROVE_AMOUNT / 2;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Request unstake
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(stakeAmount);

        // Request slash for Alice prover tokens after unstake request
        MockVApp(VAPP).processSlash(ALICE_PROVER, slashAmount);

        // Skip to the end of the unstake period
        skip(UNSTAKE_PERIOD);

        // Attempt to finish unstake while there's a pending slash request - should revert
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.ProverHasSlashRequest.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishUnstake();
    }
}
