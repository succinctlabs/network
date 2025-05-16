// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {IProverRegistry} from "../src/interfaces/IProverRegistry.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";

contract SuccinctStakingRewardTests is SuccinctStakingTest {
    // A prover receives rewards and the staker receives by calling claimReward
    function test_Reward() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Record initial staked amount
        uint256 initialStaked = SuccinctStaking(STAKING).staked(STAKER_1);

        // Reward the prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that the staked amount increased by the reward
        uint256 newStaked = SuccinctStaking(STAKING).staked(STAKER_1);
        assertEq(newStaked, initialStaked + rewardAmount - 1);

        // Staker should have the reward, but should still be staked
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount + rewardAmount);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount + rewardAmount);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), stakeAmount);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
    }

    // A prover receives rewards and the staker receives them when unstaking
    function test_Reward_WhenUnstaked() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Record initial staked amount
        uint256 initialStaked = SuccinctStaking(STAKING).staked(STAKER_1);

        // Reward the prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that the staked amount increased by the reward
        uint256 newStaked = SuccinctStaking(STAKING).staked(STAKER_1);
        assertEq(newStaked, initialStaked + rewardAmount - 1);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);

        // Staker should have original stake plus the reward amount
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount + rewardAmount - 1);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 1);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 1);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0);
    }

    // Unstaking partially gives proportional rewards
    function test_Reward_WhenPartialUnstake() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = stakeAmount / 2;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Record initial staked amount
        uint256 initialStaked = SuccinctStaking(STAKING).staked(STAKER_1);

        // Reward the prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that the staked amount increased by the reward
        uint256 newStaked = SuccinctStaking(STAKING).staked(STAKER_1);
        assertEq(newStaked, initialStaked + rewardAmount - 1); // Account for rounding

        // Complete partial unstake process
        _completeUnstake(STAKER_1, unstakeAmount);

        // Staker should have received part of the stake + proportional rewards
        uint256 expectedProveReceived = unstakeAmount + (rewardAmount / 2) - 1; // Account for rounding
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), expectedProveReceived);

        // Complete the rest of the unstake
        _completeUnstake(STAKER_1, unstakeAmount);

        // Staker should now have all stake + all rewards
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount + rewardAmount - 1); // Account for rounding
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

        // Record balances and initial staked amounts
        uint256 originalBalance1 = IERC20(PROVE).balanceOf(STAKER_1);
        uint256 originalBalance2 = IERC20(PROVE).balanceOf(STAKER_2);
        uint256 initialStaked1 = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 initialStaked2 = SuccinctStaking(STAKING).staked(STAKER_2);

        // Reward only to Alice prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that only STAKER_1's staked amount increased
        uint256 newStaked1 = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 newStaked2 = SuccinctStaking(STAKING).staked(STAKER_2);
        assertEq(newStaked1, initialStaked1 + rewardAmount - 2); // Account for rounding
        assertEq(newStaked2, initialStaked2); // No change for STAKER_2

        // Complete unstake process for both stakers
        _completeUnstake(STAKER_1, stakeAmount1);
        _completeUnstake(STAKER_2, stakeAmount2);

        // Staker 1 should get original stake + reward, Staker 2 only gets original stake
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1), originalBalance1 + stakeAmount1 + rewardAmount - 2
        ); // Account for rounding
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), originalBalance2 + stakeAmount2);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
        assertEq(IERC20(BOB_PROVER).balanceOf(STAKER_2), 0);
    }

    // 2 stakers, 1 prover - reward only distributed after first stake, so only first staker should
    // be able to claim rewards
    function test_Reward_WhenTwoStakersOneProverRewardOnlyDistributedAfterFirstStake() public {
        uint256 stakeAmount1 = STAKER_PROVE_AMOUNT / 2;
        uint256 stakeAmount2 = STAKER_PROVE_AMOUNT / 4;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Staker 1 to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount1);

        // Record initial staked amount for STAKER_1
        uint256 initialStaked1 = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 originalBalance1 = IERC20(PROVE).balanceOf(STAKER_1);
        // Reward to Alice prover
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount);

        // Check that STAKER_1's staked amount increased
        uint256 newStaked1 = SuccinctStaking(STAKING).staked(STAKER_1);
        assertEq(newStaked1, initialStaked1 + rewardAmount - 2); // Account for rounding

        // Staker 2 to Alice prover
        _permitAndStake(STAKER_2, STAKER_2_PK, ALICE_PROVER, stakeAmount2);

        // Record staked amounts after STAKER_2 joins
        uint256 originalBalance2 = IERC20(PROVE).balanceOf(STAKER_2);
        uint256 staked1 = SuccinctStaking(STAKING).balanceOf(STAKER_1);
        uint256 staked2 = SuccinctStaking(STAKING).balanceOf(STAKER_2);

        // Unstake
        _completeUnstake(STAKER_1, staked1);
        _completeUnstake(STAKER_2, staked2);

        // Staker 1 should get original stake + reward, Staker 2 only gets original stake
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1), originalBalance1 + stakeAmount1 + rewardAmount - 1
        );
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), originalBalance2 + stakeAmount2 - 1);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
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

        // Record initial staked amounts
        uint256 originalBalance1 = IERC20(PROVE).balanceOf(STAKER_1);
        uint256 originalBalance2 = IERC20(PROVE).balanceOf(STAKER_2);
        uint256 initialStaked1 = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 initialStaked2 = SuccinctStaking(STAKING).staked(STAKER_2);

        // Reward both provers
        MockVApp(VAPP).processReward(ALICE_PROVER, rewardAmount1);
        MockVApp(VAPP).processReward(BOB_PROVER, rewardAmount2);

        // Check that both stakers' staked amounts increased
        uint256 newStaked1 = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 newStaked2 = SuccinctStaking(STAKING).staked(STAKER_2);
        assertEq(newStaked1, initialStaked1 + rewardAmount1 - 1); // Account for rounding
        assertEq(newStaked2, initialStaked2 + rewardAmount2 - 1); // Account for rounding

        uint256 staked1 = SuccinctStaking(STAKING).balanceOf(STAKER_1);
        uint256 staked2 = SuccinctStaking(STAKING).balanceOf(STAKER_2);

        // Complete unstake process for both stakers
        _completeUnstake(STAKER_1, staked1);
        _completeUnstake(STAKER_2, staked2);

        // Each staker gets their original stake plus rewards for their delegated prover
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1), originalBalance1 + stakeAmount1 + rewardAmount1 - 1
        );
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_2), originalBalance2 + stakeAmount2 + rewardAmount2 - 1
        );
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKER_1), 0);
        assertEq(IERC20(BOB_PROVER).balanceOf(STAKER_2), 0);
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

        vm.expectRevert(abi.encodeWithSelector(IProverRegistry.ProverNotFound.selector));
        MockVApp(VAPP).processReward(unknownProver, rewardAmount);
    }
}
