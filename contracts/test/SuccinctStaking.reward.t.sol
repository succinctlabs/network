// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";

contract SuccinctStakingRewardTests is SuccinctStakingTest {
    struct BalanceSnapshot {
        uint256 staker1Balance;
        uint256 staker2Balance;
        uint256 aliceBalance;
        uint256 bobBalance;
        uint256 staker1Staked;
        uint256 staker2Staked;
    }

    /// @dev For stack-too-deep workaround
    function _takeSnapshot() internal view returns (BalanceSnapshot memory) {
        return BalanceSnapshot({
            staker1Balance: IERC20(PROVE).balanceOf(STAKER_1),
            staker2Balance: IERC20(PROVE).balanceOf(STAKER_2),
            aliceBalance: IERC20(PROVE).balanceOf(ALICE),
            bobBalance: IERC20(PROVE).balanceOf(BOB),
            staker1Staked: SuccinctStaking(STAKING).staked(STAKER_1),
            staker2Staked: SuccinctStaking(STAKING).staked(STAKER_2)
        });
    }

    // A prover receives rewards and the staker receives by calling claimReward
    function test_Reward() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        BalanceSnapshot memory before = _takeSnapshot();

        // Calculate expected reward split
        (uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateRewardSplit(rewardAmount);

        // Reward the prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that the staked amount increased by the staker reward portion
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            before.staker1Staked + expectedStakerReward - 1
        );

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward);

        // Staker should have the reward, but should still be staked
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount + expectedStakerReward);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount + expectedStakerReward);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), stakeAmount);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
    }

    // A prover receives rewards and the staker receives them when unstaking
    function test_Reward_WhenUnstaked() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        BalanceSnapshot memory before = _takeSnapshot();

        // Calculate expected reward split
        (uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateRewardSplit(rewardAmount);

        // Reward the prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that the staked amount increased by the staker reward portion
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            before.staker1Staked + expectedStakerReward - 1
        );

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);

        // Staker should have original stake plus the staker reward amount
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount + expectedStakerReward - 1);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 1);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 1);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0);
    }

    // Unstaking partially gives proportional rewards
    function test_Reward_WhenPartialUnstake() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = stakeAmount / 2;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        BalanceSnapshot memory before = _takeSnapshot();

        // Calculate expected reward split
        (uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateRewardSplit(rewardAmount);

        // Reward the prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that the staked amount increased by the staker reward portion
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            before.staker1Staked + expectedStakerReward - 1
        );

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward);

        // Complete partial unstake process
        _completeUnstake(STAKER_1, unstakeAmount);

        // Staker should have received part of the stake + proportional rewards
        uint256 expectedProveReceived = unstakeAmount + (expectedStakerReward / 2) - 1; // Account for rounding
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), expectedProveReceived);

        // Complete the rest of the unstake
        _completeUnstake(STAKER_1, unstakeAmount);

        // Staker should now have all stake + all staker rewards
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount + expectedStakerReward - 1);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0);
    }

    // 2 stakers, 2 provers - reward for only a single prover
    function test_Reward_WhenTwoStakersTwoProversOneRewarded() public {
        uint256 stakeAmount1 = STAKER_PROVE_AMOUNT / 2;
        uint256 stakeAmount2 = STAKER_PROVE_AMOUNT / 4;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Each staker deposits to a different prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount1);
        _permitAndStake(STAKER_2, STAKER_2_PK, BOB_PROVER, stakeAmount2);

        BalanceSnapshot memory before = _takeSnapshot();

        // Calculate expected reward split
        (uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateRewardSplit(rewardAmount);

        // Reward only to Alice prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that only STAKER_1's staked amount increased
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            before.staker1Staked + expectedStakerReward - 1
        );
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), before.staker2Staked); // No change for STAKER_2

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward);

        // Complete unstake process for both stakers
        _completeUnstake(STAKER_1, stakeAmount1);
        _completeUnstake(STAKER_2, stakeAmount2);

        // Staker 1 should get original stake + staker reward, Staker 2 only gets original stake
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1),
            before.staker1Balance + stakeAmount1 + expectedStakerReward - 1
        );
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), before.staker2Balance + stakeAmount2);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
        assertEq(IERC20(BOB_PROVER).balanceOf(STAKER_2), 0);
    }

    // 2 stakers, 1 prover - reward only distributed after first stake
    function test_Reward_WhenTwoStakersOneProverRewardOnlyDistributedAfterFirstStake() public {
        uint256 stakeAmount1 = STAKER_PROVE_AMOUNT / 2;
        uint256 stakeAmount2 = STAKER_PROVE_AMOUNT / 4;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Staker 1 to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount1);

        BalanceSnapshot memory beforeReward = _takeSnapshot();

        // Calculate expected reward split
        (uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateRewardSplit(rewardAmount);

        // Reward to Alice prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that STAKER_1's staked amount increased
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            beforeReward.staker1Staked + expectedStakerReward - 1
        );

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), beforeReward.aliceBalance + expectedOwnerReward);

        // Staker 2 to Alice prover
        _permitAndStake(STAKER_2, STAKER_2_PK, ALICE_PROVER, stakeAmount2);

        // Take snapshot after STAKER_2 joins
        BalanceSnapshot memory afterStake2 = _takeSnapshot();

        // Unstake
        _completeUnstake(STAKER_1, SuccinctStaking(STAKING).balanceOf(STAKER_1));
        _completeUnstake(STAKER_2, SuccinctStaking(STAKING).balanceOf(STAKER_2));

        // Staker 1 should get original stake + staker reward, Staker 2 only gets original stake
        // Allow for 1 wei difference due to rounding
        uint256 actualBalance1 = IERC20(PROVE).balanceOf(STAKER_1);
        uint256 expectedBalance1 = beforeReward.staker1Balance + stakeAmount1 + expectedStakerReward;
        assertTrue(actualBalance1 >= expectedBalance1 - 1 && actualBalance1 <= expectedBalance1);

        assertEq(IERC20(PROVE).balanceOf(STAKER_2), afterStake2.staker2Balance + stakeAmount2 - 1);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_2), 0);
    }

    // 2 stakers, 1 prover - reward distributed after both stake
    function test_Reward_WhenTwoStakersOneProverRewardDistributedAfterBothStake() public {
        uint256 stakeAmount1 = STAKER_PROVE_AMOUNT / 2;
        uint256 stakeAmount2 = STAKER_PROVE_AMOUNT / 4;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Both stakers to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount1);
        _permitAndStake(STAKER_2, STAKER_2_PK, ALICE_PROVER, stakeAmount2);

        BalanceSnapshot memory before = _takeSnapshot();

        // Calculate expected reward split
        (uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateRewardSplit(rewardAmount);

        // Reward to Alice prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward);

        // Unstake
        uint256 staked1 = SuccinctStaking(STAKING).balanceOf(STAKER_1);
        uint256 staked2 = SuccinctStaking(STAKING).balanceOf(STAKER_2);
        _completeUnstake(STAKER_1, staked1);
        _completeUnstake(STAKER_2, staked2);

        // Calculate expected rewards for each staker based on their proportional stake
        uint256 totalStake = stakeAmount1 + stakeAmount2;
        uint256 expectedReward1 = (expectedStakerReward * stakeAmount1) / totalStake;
        uint256 expectedReward2 = (expectedStakerReward * stakeAmount2) / totalStake;

        // Both stakers should get their original stake + proportional staker reward
        // Allow for 1 wei difference due to rounding
        uint256 actualBalance1 = IERC20(PROVE).balanceOf(STAKER_1);
        uint256 expectedBalance1 = before.staker1Balance + stakeAmount1 + expectedReward1;
        assertTrue(actualBalance1 >= expectedBalance1 - 1 && actualBalance1 <= expectedBalance1);

        uint256 actualBalance2 = IERC20(PROVE).balanceOf(STAKER_2);
        uint256 expectedBalance2 = before.staker2Balance + stakeAmount2 + expectedReward2;
        assertTrue(actualBalance2 >= expectedBalance2 - 1 && actualBalance2 <= expectedBalance2);

        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_2), 0);
    }

    // 2 stakers, 2 provers - rewards for both provers
    function test_Reward_WhenTwoStakersTwoProversBothRewarded() public {
        uint256 stakeAmount1 = STAKER_PROVE_AMOUNT / 2;
        uint256 stakeAmount2 = STAKER_PROVE_AMOUNT / 4;
        uint256 rewardAmount1 = STAKER_PROVE_AMOUNT / 2;
        uint256 rewardAmount2 = STAKER_PROVE_AMOUNT / 4;

        // Each staker deposits to a different prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount1);
        _permitAndStake(STAKER_2, STAKER_2_PK, BOB_PROVER, stakeAmount2);

        BalanceSnapshot memory before = _takeSnapshot();

        // Calculate expected reward splits
        (uint256 expectedStakerReward1, uint256 expectedOwnerReward1) =
            _calculateRewardSplit(rewardAmount1);
        (uint256 expectedStakerReward2, uint256 expectedOwnerReward2) =
            _calculateRewardSplit(rewardAmount2);

        // Reward both provers
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount1);
        MockVApp(VAPP).processReward(BOB_PROVER, rewardAmount2);

        // Check that both stakers' staked amounts increased by the staker portion
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            before.staker1Staked + expectedStakerReward1 - 1
        );
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_2),
            before.staker2Staked + expectedStakerReward2 - 1
        );

        // Check that prover owners received their portions of the rewards
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward1);
        assertEq(IERC20(PROVE).balanceOf(BOB), before.bobBalance + expectedOwnerReward2);

        // Complete unstake process for both stakers
        _completeUnstake(STAKER_1, SuccinctStaking(STAKING).balanceOf(STAKER_1));
        _completeUnstake(STAKER_2, SuccinctStaking(STAKING).balanceOf(STAKER_2));

        // Each staker gets their original stake plus staker rewards for their delegated prover
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1),
            before.staker1Balance + stakeAmount1 + expectedStakerReward1 - 1
        );
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_2),
            before.staker2Balance + stakeAmount2 + expectedStakerReward2 - 1
        );
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
        assertEq(IERC20(BOB_PROVER).balanceOf(STAKING), 0);
    }

    function test_RevertReward_WhenProverHasNotStaked() public {
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Reward the prover
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.NotStaked.selector));
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);
    }

    function test_RevertReward_WhenProverNotFound() public {
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;
        address unknownProver = makeAddr("UNKNOWN_PROVER");

        vm.expectRevert();
        MockVApp(VAPP).processReward(unknownProver, rewardAmount);
    }
}
