// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IProver} from "../src/interfaces/IProver.sol";

contract SuccinctStakingFulfillmentTests is SuccinctStakingTest {
    /// @dev For stack-too-deep workaround
    struct BalanceSnapshot {
        uint256 staker1Balance;
        uint256 staker2Balance;
        uint256 aliceBalance;
        uint256 bobBalance;
        uint256 staker1Staked;
        uint256 staker2Staked;
        uint256 feeVaultBalance;
        uint256 vappBalance;
    }

    function _takeSnapshot() internal view returns (BalanceSnapshot memory) {
        return BalanceSnapshot({
            staker1Balance: IERC20(PROVE).balanceOf(STAKER_1),
            staker2Balance: IERC20(PROVE).balanceOf(STAKER_2),
            aliceBalance: IERC20(PROVE).balanceOf(ALICE),
            bobBalance: IERC20(PROVE).balanceOf(BOB),
            staker1Staked: SuccinctStaking(STAKING).staked(STAKER_1),
            staker2Staked: SuccinctStaking(STAKING).staked(STAKER_2),
            feeVaultBalance: IERC20(PROVE).balanceOf(TREASURY),
            vappBalance: IERC20(PROVE).balanceOf(VAPP)
        });
    }

    // A prover receives rewards and the staker receives by calling claimReward
    function test_Reward_WhenValid() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        BalanceSnapshot memory before = _takeSnapshot();

        // Calculate expected reward split including protocol fee
        _calculateFullRewardSplit(rewardAmount);

        // Reward the prover
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Simulate withdrawals from VApp to make actual token transfers
        // Withdraw actual balances instead of expected amounts to avoid rounding issues
        uint256 actualProtocolFee = _withdrawFullBalanceFromVApp(TREASURY);
        uint256 actualOwnerReward = _withdrawFullBalanceFromVApp(ALICE);
        uint256 actualStakerReward = _withdrawFullBalanceFromVApp(ALICE_PROVER);

        // Check that the staked amount increased by the staker reward portion
        assertApproxEqAbs(
            SuccinctStaking(STAKING).staked(STAKER_1), before.staker1Staked + actualStakerReward, 1
        );

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + actualOwnerReward);

        // Check that protocol fee was transferred to TREASURY
        assertEq(IERC20(PROVE).balanceOf(TREASURY), before.feeVaultBalance + actualProtocolFee);

        // Staker should have the reward, but should still be staked
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertApproxEqAbs(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount + actualStakerReward, 1);
        assertApproxEqAbs(
            IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount + actualStakerReward, 1
        );
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

        // Calculate expected reward split including protocol fee
        (uint256 expectedProtocolFee, uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateFullRewardSplit(rewardAmount);

        // Reward the prover
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Simulate withdrawals from VApp to make actual token transfers
        _withdrawFromVApp(TREASURY, expectedProtocolFee);
        _withdrawFromVApp(ALICE, expectedOwnerReward);
        _withdrawFromVApp(ALICE_PROVER, expectedStakerReward);

        // Check that the staked amount increased by the staker reward portion
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            before.staker1Staked + expectedStakerReward - 1
        );

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward);

        // Check that protocol fee was transferred to TREASURY
        assertEq(IERC20(PROVE).balanceOf(TREASURY), before.feeVaultBalance + expectedProtocolFee);

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

        // Calculate expected reward split including protocol fee
        (uint256 expectedProtocolFee, uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateFullRewardSplit(rewardAmount);

        // Reward the prover
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Simulate withdrawals from VApp to make actual token transfers
        _withdrawFromVApp(TREASURY, expectedProtocolFee);
        _withdrawFromVApp(ALICE, expectedOwnerReward);
        _withdrawFromVApp(ALICE_PROVER, expectedStakerReward);

        // Check that the staked amount increased by the staker reward portion
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            before.staker1Staked + expectedStakerReward - 1
        );

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward);

        // Check that protocol fee was transferred to TREASURY
        assertEq(IERC20(PROVE).balanceOf(TREASURY), before.feeVaultBalance + expectedProtocolFee);

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

        // Calculate expected reward split including protocol fee
        (uint256 expectedProtocolFee, uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateFullRewardSplit(rewardAmount);

        // Reward only to Alice prover
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Simulate withdrawals from VApp to make actual token transfers
        _withdrawFromVApp(TREASURY, expectedProtocolFee);
        _withdrawFromVApp(ALICE, expectedOwnerReward);
        _withdrawFromVApp(ALICE_PROVER, expectedStakerReward);

        // Check that only STAKER_1's staked amount increased
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            before.staker1Staked + expectedStakerReward - 1
        );
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), before.staker2Staked); // No change for STAKER_2

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward);

        // Check that protocol fee was transferred to TREASURY
        assertEq(IERC20(PROVE).balanceOf(TREASURY), before.feeVaultBalance + expectedProtocolFee);

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

        // Calculate expected reward split including protocol fee
        (uint256 expectedProtocolFee, uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateFullRewardSplit(rewardAmount);

        // Reward to Alice prover
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Simulate withdrawals from VApp to make actual token transfers
        _withdrawFromVApp(TREASURY, expectedProtocolFee);
        _withdrawFromVApp(ALICE, expectedOwnerReward);
        _withdrawFromVApp(ALICE_PROVER, expectedStakerReward);

        // Check that STAKER_1's staked amount increased
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_1),
            beforeReward.staker1Staked + expectedStakerReward - 1
        );

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), beforeReward.aliceBalance + expectedOwnerReward);

        // Check that protocol fee was transferred to TREASURY
        assertEq(
            IERC20(PROVE).balanceOf(TREASURY), beforeReward.feeVaultBalance + expectedProtocolFee
        );

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

        // Calculate expected reward split including protocol fee
        (uint256 expectedProtocolFee, uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateFullRewardSplit(rewardAmount);

        // Reward to Alice prover
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Simulate withdrawals from VApp to make actual token transfers
        _withdrawFromVApp(TREASURY, expectedProtocolFee);
        _withdrawFromVApp(ALICE, expectedOwnerReward);
        _withdrawFromVApp(ALICE_PROVER, expectedStakerReward);

        // Check that Alice (prover owner) received her portion of the reward
        assertEq(IERC20(PROVE).balanceOf(ALICE), before.aliceBalance + expectedOwnerReward);

        // Check that protocol fee was transferred to TREASURY
        assertEq(IERC20(PROVE).balanceOf(TREASURY), before.feeVaultBalance + expectedProtocolFee);

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

        // Calculate expected reward splits including protocol fees
        (uint256 expectedProtocolFee1, uint256 expectedStakerReward1, uint256 expectedOwnerReward1)
        = _calculateFullRewardSplit(rewardAmount1);
        (uint256 expectedProtocolFee2, uint256 expectedStakerReward2, uint256 expectedOwnerReward2)
        = _calculateFullRewardSplit(rewardAmount2);

        // Reward both provers
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount1);
        MockVApp(VAPP).processFulfillment(BOB_PROVER, rewardAmount2);

        // Simulate withdrawals from VApp to make actual token transfers
        _withdrawFromVApp(TREASURY, expectedProtocolFee1 + expectedProtocolFee2);
        _withdrawFromVApp(ALICE, expectedOwnerReward1);
        _withdrawFromVApp(BOB, expectedOwnerReward2);
        _withdrawFromVApp(ALICE_PROVER, expectedStakerReward1);
        _withdrawFromVApp(BOB_PROVER, expectedStakerReward2);

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

        // Check that protocol fees were transferred to TREASURY
        assertEq(
            IERC20(PROVE).balanceOf(TREASURY),
            before.feeVaultBalance + expectedProtocolFee1 + expectedProtocolFee2
        );

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

    function test_RevertReward_WhenProverNotFound() public {
        uint256 rewardAmount = STAKER_PROVE_AMOUNT;
        address unknownProver = makeAddr("UNKNOWN_PROVER");

        vm.expectRevert();
        MockVApp(VAPP).processFulfillment(unknownProver, rewardAmount);
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Reward_WhenVariableAmounts(uint256 _rewardAmount) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        // Start with a minimum that ensures non-zero fees
        uint256 rewardAmount = bound(_rewardAmount, 1000, REQUESTER_PROVE_AMOUNT);

        // Stake
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Process reward
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Calculate expected splits
        (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward) =
            _calculateFullRewardSplit(rewardAmount);

        // Withdraw rewards only if amounts are non-zero
        if (protocolFee > 0) _withdrawFromVApp(TREASURY, protocolFee);
        if (ownerReward > 0) _withdrawFromVApp(ALICE, ownerReward);
        if (stakerReward > 0) _withdrawFromVApp(ALICE_PROVER, stakerReward);

        // Verify staker received reward
        assertApproxEqAbs(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount + stakerReward, 1);
    }

    function testFuzz_Reward_WhenMultipleStakers(
        uint256[3] memory _stakeAmounts,
        uint256 _rewardAmount
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

        uint256 rewardAmount = bound(_rewardAmount, 1000, REQUESTER_PROVE_AMOUNT / 2);

        // Process reward
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Calculate and withdraw
        (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward) =
            _calculateFullRewardSplit(rewardAmount);
        _withdrawFromVApp(TREASURY, protocolFee);
        _withdrawFromVApp(ALICE, ownerReward);
        _withdrawFromVApp(ALICE_PROVER, stakerReward);

        // Verify proportional distribution
        for (uint256 i = 0; i < stakers.length; i++) {
            uint256 expectedReward = (stakerReward * _stakeAmounts[i]) / totalStaked;
            uint256 actualStaked = SuccinctStaking(STAKING).staked(stakers[i]);
            uint256 expectedStaked = _stakeAmounts[i] + expectedReward;

            // Calculate tolerance as 0.01% of expected value (1 part in 10,000)
            uint256 tolerance = expectedStaked / 10_000 + 1;
            assertApproxEqAbs(
                actualStaked, expectedStaked, tolerance, "Staker should receive proportional reward"
            );
        }
    }

    function testFuzz_Reward_WhenWithPartialUnstake(uint256 _unstakePercent, uint256 _rewardAmount)
        public
    {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakePercent = bound(_unstakePercent, 10, 90); // 10-90% unstake
        uint256 unstakeAmount = (stakeAmount * unstakePercent) / 100;
        uint256 rewardAmount = bound(_rewardAmount, 1000, REQUESTER_PROVE_AMOUNT / 4);

        // Stake
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request partial unstake
        _requestUnstake(STAKER_1, unstakeAmount);

        // Process reward while unstaking
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Calculate and withdraw
        (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward) =
            _calculateFullRewardSplit(rewardAmount);
        _withdrawFromVApp(TREASURY, protocolFee);
        _withdrawFromVApp(ALICE, ownerReward);
        _withdrawFromVApp(ALICE_PROVER, stakerReward);

        // Complete unstake
        skip(UNSTAKE_PERIOD);
        uint256 receivedAmount = _finishUnstake(STAKER_1);

        // Verify unstaked amount doesn't include new rewards
        assertApproxEqAbs(receivedAmount, unstakeAmount, 1);

        // Verify remaining stake includes proportional reward
        uint256 remainingStake = stakeAmount - unstakeAmount;
        uint256 expectedRemainingWithReward = remainingStake + stakerReward;
        assertApproxEqAbs(
            SuccinctStaking(STAKING).staked(STAKER_1),
            expectedRemainingWithReward,
            3 // Slightly higher tolerance for complex operation
        );
    }

    function testFuzz_Reward_WhenFeeCalculations(uint256 _stakerFeeBips) public {
        // Bound fees to reasonable ranges
        uint256 stakerFeeBips = bound(_stakerFeeBips, 0, 5000); // 0-50%

        // Create a new prover with custom staker fee
        address customProver = SuccinctStaking(STAKING).createProver(stakerFeeBips);

        // Get the owner of the custom prover
        address customProverOwner = IProver(customProver).owner();

        // Stake to custom prover
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        _stake(STAKER_1, customProver, stakeAmount);

        // Process reward
        uint256 rewardAmount = STAKER_PROVE_AMOUNT / 2;

        // Process fulfillment
        MockVApp(VAPP).processFulfillment(customProver, rewardAmount);

        // Calculate expected splits with custom staker fee
        uint256 expectedProtocolFee = (rewardAmount * PROTOCOL_FEE_BIPS) / FEE_UNIT;
        uint256 afterProtocolFee = rewardAmount - expectedProtocolFee;
        uint256 expectedStakerReward = (afterProtocolFee * stakerFeeBips) / FEE_UNIT;
        uint256 expectedOwnerReward = afterProtocolFee - expectedStakerReward;

        // Withdraw and verify (only withdraw if amounts are non-zero)
        if (expectedProtocolFee > 0) _withdrawFromVApp(TREASURY, expectedProtocolFee);
        if (expectedOwnerReward > 0) _withdrawFromVApp(customProverOwner, expectedOwnerReward);
        if (expectedStakerReward > 0) _withdrawFromVApp(customProver, expectedStakerReward);

        // Verify staker received correct reward based on custom fee
        assertApproxEqAbs(
            SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount + expectedStakerReward, 1
        );
    }

    function testFuzz_Reward_WhenMultipleProvers(uint8 _numProvers, uint256 _rewardSeed) public {
        uint256 numProvers = bound(uint256(_numProvers), 2, 5);
        address[] memory provers = new address[](numProvers);

        // Create provers and stake to them
        for (uint256 i = 0; i < numProvers; i++) {
            // Create unique prover owner for each prover
            address proverOwner = makeAddr(string.concat("PROVER_OWNER_", vm.toString(i)));
            vm.prank(proverOwner);
            provers[i] = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);

            // Different stakers for each prover
            address staker = makeAddr(string.concat("STAKER_", vm.toString(i)));
            deal(PROVE, staker, MIN_STAKE_AMOUNT);

            vm.prank(staker);
            IERC20(PROVE).approve(STAKING, MIN_STAKE_AMOUNT);
            vm.prank(staker);
            SuccinctStaking(STAKING).stake(provers[i], MIN_STAKE_AMOUNT);
        }

        // Reward random provers
        for (uint256 i = 0; i < numProvers; i++) {
            if (uint256(keccak256(abi.encode(_rewardSeed, i))) % 2 == 0) {
                uint256 rewardAmount =
                    (uint256(keccak256(abi.encode(_rewardSeed, i, "amount"))) % 1000e18) + 1;
                MockVApp(VAPP).processFulfillment(provers[i], rewardAmount);
            }
        }

        // Verify each prover's state is independent
        for (uint256 i = 0; i < numProvers; i++) {
            uint256 proverStake = SuccinctStaking(STAKING).proverStaked(provers[i]);
            assertTrue(proverStake >= MIN_STAKE_AMOUNT, "Prover stake should include initial stake");
        }
    }
}
