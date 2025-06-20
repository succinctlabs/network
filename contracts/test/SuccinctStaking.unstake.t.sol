// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

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
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount);

        // Step 1: Submit unstake request
        _requestUnstake(STAKER_1, stakeAmount);

        // Nothing should have changed
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
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
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, 0), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0);
    }

    // Someone else finishes the unstake for a staker
    function test_Unstake_WhenSomeoneElseFinishesUnstake() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = STAKER_PROVE_AMOUNT;

        // Stake some tokens to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Unstake some tokens from Alice prover
        _requestUnstake(STAKER_1, unstakeAmount);

        // Wait for the unstake period to pass
        skip(UNSTAKE_PERIOD);

        // Someone else should be able to finish the unstake
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).finishUnstake(STAKER_1);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, 0), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0);
    }

    function test_Unstake_WhenMaxClaimsEqualsClaims() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Check balances after stake
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount);

        // Submit unstake request
        _requestUnstake(STAKER_1, stakeAmount / 2);
        _requestUnstake(STAKER_1, stakeAmount / 2);

        // Wait for unstake period to pass and claim
        skip(UNSTAKE_PERIOD);

        // Claim 2/2
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishUnstake(2);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, 0), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0);
    }

    function test_Unstake_WhenMaxClaimsLessGreaterThanClaims() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Check balances after stake
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount);

        // Submit unstake request
        _requestUnstake(STAKER_1, stakeAmount / 2);
        _requestUnstake(STAKER_1, stakeAmount / 2);

        // Wait for unstake period to pass and claim
        skip(UNSTAKE_PERIOD);

        // Claim 3/2
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishUnstake(3);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, 0), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0);
    }

    function test_Unstake_WhenMaxClaimsLessThanClaims() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Check balances after stake
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount);

        // Submit unstake request
        _requestUnstake(STAKER_1, stakeAmount / 2);
        _requestUnstake(STAKER_1, stakeAmount / 2);

        // Wait for unstake period to pass and claim
        skip(UNSTAKE_PERIOD);

        // Claim 1/2
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishUnstake(1);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount / 2);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount / 2);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount / 2);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), stakeAmount / 2);
        assertEq(
            SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount / 2), stakeAmount / 2
        );
        assertEq(
            SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount / 2), stakeAmount / 2
        );
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount / 2);

        // Claim 1/1
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishUnstake(1);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
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
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Calculate expected rewards (only staker portion goes to stakers, after protocol fee)
        (uint256 expectedProtocolFee, uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateFullRewardSplit(rewardAmount);
        uint256 expectedReward1 =
            (expectedStakerReward * stakeAmount1) / (stakeAmount1 + stakeAmount2);
        uint256 expectedReward2 =
            (expectedStakerReward * stakeAmount2) / (stakeAmount1 + stakeAmount2);

        // Withdraw the rewards from VApp to make actual token transfers
        _withdrawFromVApp(FEE_VAULT, expectedProtocolFee);
        _withdrawFromVApp(ALICE, expectedOwnerReward);
        _withdrawFromVApp(ALICE_PROVER, expectedStakerReward);

        // Verify protocol fee was transferred to FEE_VAULT
        assertEq(
            IERC20(PROVE).balanceOf(FEE_VAULT),
            expectedProtocolFee,
            "Protocol fee should be transferred to FEE_VAULT"
        );

        // Verify owner reward was transferred to prover owner (ALICE)
        assertEq(
            IERC20(PROVE).balanceOf(ALICE),
            expectedOwnerReward,
            "Owner reward should be transferred to prover owner"
        );

        // Verify staked amount increased for both stakers
        uint256 stakedAfterReward1 = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 stakedAfterReward2 = SuccinctStaking(STAKING).staked(STAKER_2);
        assertApproxEqAbs(
            stakedAfterReward1,
            initialStaked1 + expectedReward1,
            1,
            "Staker 1 should receive proportional reward"
        );
        assertApproxEqAbs(
            stakedAfterReward2,
            initialStaked2 + expectedReward2,
            1,
            "Staker 2 should receive proportional reward"
        );

        // Both stakers unstake and claim
        _completeUnstake(STAKER_1, stakeAmount1);
        _completeUnstake(STAKER_2, stakeAmount2);

        // Verify final state after unstaking
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), 0);
        assertLe(
            SuccinctStaking(STAKING).proverStaked(ALICE_PROVER),
            2,
            "Should have minimal dust remaining"
        );

        // Both stakers should get their original stake plus proportional rewards
        assertApproxEqAbs(
            IERC20(PROVE).balanceOf(STAKER_1),
            STAKER_PROVE_AMOUNT + expectedReward1,
            1,
            "Staker 1 should receive original stake plus reward"
        );
        assertApproxEqAbs(
            IERC20(PROVE).balanceOf(STAKER_2),
            STAKER_PROVE_AMOUNT + expectedReward2,
            1,
            "Staker 2 should receive original stake plus reward"
        );
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
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
        MockVApp(VAPP).processFulfillment(BOB_PROVER, rewardAmount);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);
        _completeUnstake(STAKER_2, stakeAmount);

        // Verify staker only gets original stake (no rewards)
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
        assertEq(IERC20(BOB_PROVER).balanceOf(STAKING), 0);
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
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
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
        uint256 firstStakeAmount = STAKER_PROVE_AMOUNT / 2;
        uint256 secondStakeAmount = STAKER_PROVE_AMOUNT / 4;
        uint256 halfUnstakePeriod = UNSTAKE_PERIOD / 2;

        // Staker 1 deposits twice to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, firstStakeAmount);
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, secondStakeAmount);

        // Record unstaked balance
        uint256 unstakedBalance = IERC20(PROVE).balanceOf(STAKER_1);

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
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), unstakedBalance + firstStakeAmount);

        // Wait for the second unstake to be claimable
        skip(halfUnstakePeriod);

        // Claim the second unstake
        _finishUnstake(STAKER_1);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);

        // Verify both unstakes are now claimed
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1),
            unstakedBalance + firstStakeAmount + secondStakeAmount
        );
    }

    // Test unstake queue with rewards
    function test_Unstake_WhenMultipleRewards() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = 50;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Record initial staked amount
        uint256 initialStaked = SuccinctStaking(STAKING).staked(STAKER_1);

        // Add rewards before unstaking
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Calculate expected staker reward portion
        uint256 expectedStakerRewardPerReward = (rewardAmount * STAKER_FEE_BIPS) / FEE_UNIT;
        uint256 expectedStakerRewardFromFirstReward = expectedStakerRewardPerReward;

        // Withdraw the staker reward to the prover vault to increase staked amount
        _withdrawFromVApp(ALICE_PROVER, expectedStakerRewardPerReward);

        // Verify staked amount increased
        uint256 stakedAfterFirstReward = SuccinctStaking(STAKING).staked(STAKER_1);
        assertApproxEqAbs(
            stakedAfterFirstReward,
            initialStaked + expectedStakerRewardPerReward,
            1,
            "Staked amount should increase by staker reward portion"
        );

        // Unstake from Alice prover - this snapshots the iPROVE value
        _requestUnstake(STAKER_1, stakeAmount);

        // Add more rewards while tokens are in the unstake queue
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Withdraw the second staker reward to the prover vault
        _withdrawFromVApp(ALICE_PROVER, expectedStakerRewardPerReward);

        // Skip to allow claiming
        skip(UNSTAKE_PERIOD);

        // Claim unstaked tokens
        uint256 claimedAmount = _finishUnstake(STAKER_1);

        // With the new implementation, the staker only gets rewards earned BEFORE requesting unstake
        // The second reward goes back to the prover, not the unstaker
        assertApproxEqAbs(
            claimedAmount,
            stakeAmount + expectedStakerRewardFromFirstReward,
            1,
            "Claimed amount should only include rewards earned before unstake request"
        );
        assertApproxEqAbs(
            IERC20(PROVE).balanceOf(STAKER_1),
            stakeAmount + expectedStakerRewardFromFirstReward,
            1,
            "Final balance should only include rewards earned before unstake request"
        );
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
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
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
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
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
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
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
    }

    function test_RevertUnstake_WhenSomeoneElseCallsClaimUnstake() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = STAKER_PROVE_AMOUNT;

        // Stake some tokens to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Someone else should not be able to claim the unstake
        vm.expectRevert(ISuccinctStaking.NotStaked.selector);
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).finishUnstake(0);

        // Unstake some tokens from Alice prover
        _requestUnstake(STAKER_1, unstakeAmount);

        // Someone else should not be able to claim the unstake, even after unstake has been called
        vm.expectRevert(ISuccinctStaking.NotStaked.selector);
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).finishUnstake(0);
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
        SuccinctStaking(STAKING).finishUnstake(STAKER_1);
    }

    function test_Unstake_WhenSlashDuringUnstakePeriod() public {
        // Staker stakes with Alice prover.
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request unstake for the full balance.
        uint256 stPROVEBalance = IERC20(STAKING).balanceOf(STAKER_1);
        vm.prank(STAKER_1);
        ISuccinctStaking(STAKING).requestUnstake(stPROVEBalance);

        // During unstake period, a slash occurs.
        // Calculate the $iPROVE amount for the slash (50% of the prover's assets).
        uint256 proverAssets = IERC4626(ALICE_PROVER).totalAssets();
        uint256 slashAmountiPROVE = proverAssets / 2; // 50% slash in $iPROVE terms
        vm.prank(OWNER);
        MockVApp(VAPP).processSlash(ALICE_PROVER, slashAmountiPROVE);

        // Process the slash after slash period.
        skip(SLASH_PERIOD);
        vm.prank(OWNER);
        ISuccinctStaking(STAKING).finishSlash(ALICE_PROVER, 0);

        // After unstake period, finish unstake.
        skip(UNSTAKE_PERIOD);

        // The staker should receive less $PROVE due to the slash.
        vm.prank(STAKER_1);
        uint256 proveBalanceBefore = IERC20(PROVE).balanceOf(STAKER_1);
        uint256 proveReceived = ISuccinctStaking(STAKING).finishUnstake(STAKER_1);
        uint256 proveBalanceAfter = IERC20(PROVE).balanceOf(STAKER_1);

        // Verify the staker received $PROVE.
        assertEq(proveBalanceAfter - proveBalanceBefore, proveReceived);

        // The staker should receive approximately 50% of their stake due to the 50% slash.
        assertApproxEqAbs(proveReceived, stakeAmount / 2, 1, "Should receive ~50% after 50% slash");

        // Verify the prover didn't receive any rewards (since they were slashed).
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
    }

    function test_Unstake_WhenRewardDuringUnstakePeriod() public {
        // Staker stakes with Alice prover.
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Alice prover earns rewards before unstake request.
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        // Withdraw rewards to increase prover assets.
        {
            (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward) =
                _calculateFullRewardSplit(STAKER_PROVE_AMOUNT / 2);
            _withdrawFromVApp(FEE_VAULT, protocolFee);
            _withdrawFromVApp(ALICE, ownerReward);
            _withdrawFromVApp(ALICE_PROVER, stakerReward);
        }

        // Request unstake for the full balance (this snapshots the $iPROVE value).
        uint256 stPROVEBalance = IERC20(STAKING).balanceOf(STAKER_1);
        vm.prank(STAKER_1);
        ISuccinctStaking(STAKING).requestUnstake(stPROVEBalance);

        // Get the snapshot $iPROVE amount from the unstake request.
        uint256 iPROVESnapshot =
            ISuccinctStaking(STAKING).unstakeRequests(STAKER_1)[0].iPROVESnapshot;

        // More rewards are earned during unstaking period.
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, STAKER_PROVE_AMOUNT / 4);

        // Withdraw these rewards too to increase prover's $iPROVE balance.
        {
            (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward) =
                _calculateFullRewardSplit(STAKER_PROVE_AMOUNT / 4);
            _withdrawFromVApp(FEE_VAULT, protocolFee);
            _withdrawFromVApp(ALICE, ownerReward);
            _withdrawFromVApp(ALICE_PROVER, stakerReward);
        }

        // Skip to end of unstake period.
        skip(UNSTAKE_PERIOD);

        // Calculate how much $iPROVE would be redeemed for the $stPROVE (before it's burned).
        uint256 iPROVEToBeRedeemed = IERC4626(ALICE_PROVER).previewRedeem(stPROVEBalance);

        // Finish unstake.
        vm.prank(STAKER_1);
        uint256 proveReceived = ISuccinctStaking(STAKING).finishUnstake(STAKER_1);

        // Record prover's $iPROVE balance after finishing unstake.
        uint256 proverIPROVEAfter = IERC20(I_PROVE).balanceOf(ALICE_PROVER);

        // The expected difference that should have been returned to the prover.
        uint256 expectedReturnedIPROVE =
            iPROVEToBeRedeemed > iPROVESnapshot ? iPROVEToBeRedeemed - iPROVESnapshot : 0;

        // Verify results:
        // The staker should receive $PROVE based on the snapshot (only rewards before unstake request).
        assertApproxEqAbs(
            proveReceived,
            IERC4626(I_PROVE).previewRedeem(iPROVESnapshot),
            1,
            "Staker should receive $PROVE based on snapshot $iPROVE"
        );

        // The prover should receive back the $iPROVE difference (rewards earned during unstaking).
        // The prover's balance will be: initial balance - redeemed amount + returned difference.
        // We verify that the prover has approximately the expected returned $iPROVE.
        assertApproxEqAbs(
            proverIPROVEAfter,
            expectedReturnedIPROVE,
            2,
            "Prover should have the $iPROVE difference from rewards during unstaking"
        );

        // Verify that the total $iPROVE is conserved (no $iPROVE is lost).
        assertEq(
            IERC20(I_PROVE).balanceOf(STAKING), 0, "Staking contract should have no $iPROVE left"
        );
    }

    function testFuzz_Unstake_PartialAmount(uint256 _unstakeAmount) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = bound(_unstakeAmount, 1, stakeAmount);

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request partial unstake
        _requestUnstake(STAKER_1, unstakeAmount);

        // Check that unstake pending matches requested amount
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), unstakeAmount);

        // Check that staked amount hasn't changed yet
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);

        // Wait and complete unstake
        skip(UNSTAKE_PERIOD);
        uint256 receivedAmount = _finishUnstake(STAKER_1);

        // Verify amounts
        assertEq(receivedAmount, unstakeAmount);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount - unstakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount - unstakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), unstakeAmount);
    }

    function testFuzz_Unstake_WithDispenseRewards(uint256 _dispenseAmount, uint256 _unstakeAmount)
        public
    {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 dispenseAmount = bound(_dispenseAmount, 1000, 1_000_000e18);
        uint256 unstakeAmount = bound(_unstakeAmount, 1, stakeAmount);

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Dispense rewards
        _dispense(dispenseAmount);

        // Get staked amount after dispense
        uint256 stakedAfterDispense = SuccinctStaking(STAKING).staked(STAKER_1);
        assertApproxEqAbs(stakedAfterDispense, stakeAmount + dispenseAmount, 10);

        // Request unstake
        _requestUnstake(STAKER_1, unstakeAmount);

        // Complete unstake
        skip(UNSTAKE_PERIOD);
        uint256 receivedAmount = _finishUnstake(STAKER_1);

        // Should receive proportional share of the rewards
        uint256 expectedReceived = (unstakeAmount * stakedAfterDispense) / stakeAmount;
        assertApproxEqAbs(receivedAmount, expectedReceived, 10);
    }

    function testFuzz_Unstake_MultipleRequests(uint256[3] memory _amounts) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Bound each unstake amount
        uint256 totalUnstake = 0;
        for (uint256 i = 0; i < _amounts.length; i++) {
            _amounts[i] = bound(_amounts[i], MIN_STAKE_AMOUNT, stakeAmount / 4);
            totalUnstake += _amounts[i];
        }

        // Ensure we don't unstake more than staked
        vm.assume(totalUnstake <= stakeAmount);

        // Stake initial amount
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Make multiple unstake requests
        for (uint256 i = 0; i < _amounts.length; i++) {
            _requestUnstake(STAKER_1, _amounts[i]);
            skip(1 days); // Add some time between requests
        }

        // Check total pending
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), totalUnstake);

        // Wait for all to mature
        skip(UNSTAKE_PERIOD);

        // Finish unstake
        uint256 totalReceived = _finishUnstake(STAKER_1);

        assertEq(totalReceived, totalUnstake);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount - totalUnstake);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), totalUnstake);
    }

    function testFuzz_Unstake_WithSlashDuringUnstakePeriod(uint256 _slashAmount) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = stakeAmount;
        uint256 slashAmount = bound(_slashAmount, 1, stakeAmount / 2);

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request unstake
        _requestUnstake(STAKER_1, unstakeAmount);

        // Slash during unstake period
        skip(UNSTAKE_PERIOD / 2);
        _requestSlash(ALICE_PROVER, slashAmount);
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, 0);

        // Complete unstake after slash
        skip(UNSTAKE_PERIOD / 2);
        uint256 receivedAmount = _finishUnstake(STAKER_1);

        // Should receive reduced amount due to slash
        assertApproxEqAbs(receivedAmount, stakeAmount - slashAmount, 10);
    }

    function testFuzz_Unstake_TimingBeforeAndAfterPeriod(uint256 _waitTime) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake and request unstake
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _requestUnstake(STAKER_1, stakeAmount);

        // Bound wait time around unstake period
        uint256 waitTime = bound(_waitTime, 1, UNSTAKE_PERIOD * 2);
        skip(waitTime);

        uint256 receivedAmount = _finishUnstake(STAKER_1);

        if (waitTime < UNSTAKE_PERIOD) {
            // Should not receive anything yet
            assertEq(receivedAmount, 0);
            assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        } else {
            // Should receive the full amount
            assertEq(receivedAmount, stakeAmount);
            assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount);
        }

        SuccinctStaking(STAKING).finishUnstake(STAKER_1, 0);
    }
}
