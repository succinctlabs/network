// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

contract SuccinctStakingUnstakeTests is SuccinctStakingTest {
    function test_Unstake_WhenValid() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Sanity check
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewUnstake(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewUnstake(ALICE_PROVER, 0), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0);

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Check balances after stake
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewUnstake(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount);

        // Get escrow pool state before unstake
        ISuccinctStaking.EscrowPool memory poolBefore =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(poolBefore.iPROVEEscrow, 0, "Escrow should be 0 before unstake");
        assertEq(poolBefore.slashFactor, 0, "Slash factor should be 0 before init");

        // Step 1: Submit unstake request
        vm.expectEmit(true, true, true, true);
        emit ISuccinctStaking.UnstakeRequest(STAKER_1, ALICE_PROVER, stakeAmount, stakeAmount);
        _requestUnstake(STAKER_1, stakeAmount);

        // After request unstake: stPROVE burned, iPROVE escrowed
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0, "stPROVE should be burned");
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0, "Staked amount should be 0");
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0, "PROVE balance unchanged");
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0, "Prover iPROVE should be 0");
        assertEq(
            SuccinctStaking(STAKING).unstakePending(STAKER_1),
            stakeAmount,
            "Pending should match request"
        );
        assertEq(
            SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0, "Prover staked should be 0"
        );

        // Check escrow pool after unstake
        ISuccinctStaking.EscrowPool memory poolAfter =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(poolAfter.iPROVEEscrow, stakeAmount, "Escrow should contain unstaked iPROVE");
        assertEq(poolAfter.slashFactor, SCALAR, "Slash factor should be 1e27 after init");
        assertEq(
            IERC20(I_PROVE).balanceOf(STAKING), stakeAmount, "Staking contract should hold iPROVE"
        );

        // Step 2: Wait for unstake period to pass and claim
        skip(UNSTAKE_PERIOD);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctStaking.Unstake(STAKER_1, ALICE_PROVER, stakeAmount, stakeAmount);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctStaking.ProverUnbound(STAKER_1, ALICE_PROVER);

        uint256 proveReceived = _finishUnstake(STAKER_1);

        // Verify final state
        assertEq(proveReceived, stakeAmount, "Should receive full stake amount");
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1), stakeAmount, "STAKER_1 should have received PROVE"
        );
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewUnstake(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewUnstake(ALICE_PROVER, 0), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0);

        // Check escrow pool is cleared
        ISuccinctStaking.EscrowPool memory poolFinal =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(poolFinal.iPROVEEscrow, 0, "Escrow should be cleared after unstake");
        assertEq(poolFinal.slashFactor, SCALAR, "Slash factor should be reset");
        assertEq(IERC20(I_PROVE).balanceOf(STAKING), 0, "Staking contract should have no iPROVE");
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
        assertEq(SuccinctStaking(STAKING).previewUnstake(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).previewUnstake(ALICE_PROVER, 0), 0);
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
        _withdrawFromVApp(TREASURY, expectedProtocolFee);
        _withdrawFromVApp(ALICE, expectedOwnerReward);
        _withdrawFromVApp(ALICE_PROVER, expectedStakerReward);

        // Verify protocol fee was transferred to TREASURY
        assertEq(
            IERC20(PROVE).balanceOf(TREASURY),
            expectedProtocolFee,
            "Protocol fee should be transferred to TREASURY"
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
        vm.prank(DISPENSER);
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

        // Verify stPROVE was burned immediately
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0, "stPROVE should be burned");

        // Verify iPROVE is escrowed
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(pool.iPROVEEscrow, stakeAmount, "iPROVE should be escrowed");

        // Wait for less than the unstake period
        skip(partialUnstakePeriod);

        // Try to claim unstaked tokens early - should not receive tokens yet
        uint256 proveReceived = _finishUnstake(STAKER_1);
        assertEq(proveReceived, 0, "Should not receive tokens early");

        // Verify that tokens are still not received
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);

        // Wait for the rest of the unstake period
        skip(1 days);

        // Claim unstaked tokens after the full period
        proveReceived = _finishUnstake(STAKER_1);

        // Now tokens should be received
        assertEq(proveReceived, stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount);

        // Verify escrow is cleared
        pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(pool.iPROVEEscrow, 0, "Escrow should be cleared");
    }

    // Tests that unstaking still works after a prover is fully slashed before
    // requestUnstake is called.
    function test_Unstake_WhenProverFullSlashBeforeEscrow() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 slashAmount = stakeAmount;

        // Stake 1 stakes to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Full slash to deactivate prover
        _completeSlash(ALICE_PROVER, slashAmount);
        assertTrue(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Staker 1 requests unstakes from prover
        _requestUnstake(STAKER_1, stakeAmount);

        // Wait for unstake period
        skip(UNSTAKE_PERIOD);

        // Finishes unstake
        uint256 proveReceived = _finishUnstake(STAKER_1);
        assertEq(proveReceived, 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
    }

    // Tests that unstaking still works after a prover is fully slashed after
    // requestUnstake is called.
    function test_Unstake_WhenProverFullSlashAfterEscrow() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 slashAmount = stakeAmount;

        // Stake 1 stakes to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Staker 1 requests unstakes from prover
        _requestUnstake(STAKER_1, stakeAmount);

        // Full slash, but because the iPROVE is already escrowed the prover won't become
        // deactivated
        _completeSlash(ALICE_PROVER, slashAmount);
        assertFalse(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Wait for unstake period
        skip(UNSTAKE_PERIOD);

        // Finishes unstake
        uint256 proveReceived = _finishUnstake(STAKER_1);
        assertEq(proveReceived, 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
    }

    // Tests that unstaking still works after a prover is partially slashed before
    // requestUnstake is called.
    function test_Unstake_WhenProverPartialSlashBeforeEscrow() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 leftoverAssets = 1e9;
        uint256 slashAmount = stakeAmount - leftoverAssets;

        // Stake 1 stakes to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Slash *almost* everything: leave 1 gwei PROVE (= 1e9 wei)
        _completeSlash(ALICE_PROVER, slashAmount);
        assertTrue(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Staker 1 requests unstake from prover
        _requestUnstake(STAKER_1, stakeAmount);

        // Wait for unstake period
        skip(UNSTAKE_PERIOD);

        // Finish unstake
        uint256 proveReceived = _finishUnstake(STAKER_1);
        assertEq(proveReceived, leftoverAssets);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), leftoverAssets);
    }

    // Tests that unstaking still works after a prover is partially slashed after
    // requestUnstake is called.
    function test_Unstake_WhenProverPartialSlashAfterEscrow() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 leftoverAssets = 1e9;
        uint256 slashAmount = stakeAmount - leftoverAssets;

        // Stake 1 stakes to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Staker 1 requests unstake from prover
        _requestUnstake(STAKER_1, stakeAmount);

        // Slash *almost* everything: leave 1 gwei PROVE (= 1e9 wei), but because the iPROVE is
        // already escrowed the prover won't become deactivated
        _completeSlash(ALICE_PROVER, slashAmount);
        assertFalse(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Wait for unstake period
        skip(UNSTAKE_PERIOD);

        // Finish unstake
        uint256 proveReceived = _finishUnstake(STAKER_1);
        assertEq(proveReceived, leftoverAssets);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), leftoverAssets);
    }

    // Test multiple unstakes in the queue
    function test_Unstake_WhenMultipleUnstakes() public {
        uint256 totalStakeAmount = STAKER_PROVE_AMOUNT;

        // With new implementation, can only create unstake requests up to maxUnstakeRequests
        // and validation prevents unstaking more than balance minus pending
        uint256 maxRequests = SuccinctStaking(STAKING).maxUnstakeRequests();
        require(maxRequests >= 2, "Test requires at least 2 max unstake requests");

        // Test strategy: stake, unstake partially, wait, finish unstake, then unstake again
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, totalStakeAmount);

        // Record initial balance
        uint256 initialProveBalance = IERC20(PROVE).balanceOf(STAKER_1);

        // First unstake half
        uint256 firstUnstakeAmount = totalStakeAmount / 2;
        _requestUnstake(STAKER_1, firstUnstakeAmount);

        // Verify state after first unstake
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), firstUnstakeAmount);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), totalStakeAmount - firstUnstakeAmount);

        // Wait for first unstake to mature
        skip(UNSTAKE_PERIOD);

        // Finish first unstake
        uint256 firstReceived = _finishUnstake(STAKER_1);
        assertEq(firstReceived, firstUnstakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), initialProveBalance + firstUnstakeAmount);

        // Now we can create a second unstake request since the first is cleared
        uint256 secondUnstakeAmount = totalStakeAmount - firstUnstakeAmount;
        _requestUnstake(STAKER_1, secondUnstakeAmount);

        // Verify state after second unstake
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), secondUnstakeAmount);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0, "All stPROVE should be burned");

        // Wait and finish second unstake
        skip(UNSTAKE_PERIOD);
        uint256 secondReceived = _finishUnstake(STAKER_1);
        assertEq(secondReceived, secondUnstakeAmount);

        // Verify final state
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1),
            initialProveBalance + totalStakeAmount,
            "Should receive back full stake amount"
        );
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);

        // Verify escrow is cleared
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(pool.iPROVEEscrow, 0, "Escrow should be cleared");
    }

    // Test unstake queue with rewards
    function test_Unstake_WhenMultipleRewards() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = STAKER_PROVE_AMOUNT / 4;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Record initial staked amount
        uint256 initialStaked = SuccinctStaking(STAKING).staked(STAKER_1);

        // Add rewards before unstaking
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Calculate expected rewards
        (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward) =
            _calculateFullRewardSplit(rewardAmount);

        // Withdraw the rewards to their respective recipients
        _withdrawFromVApp(TREASURY, protocolFee);
        _withdrawFromVApp(ALICE, ownerReward);
        _withdrawFromVApp(ALICE_PROVER, stakerReward);

        // Verify staked amount increased
        uint256 stakedAfterFirstReward = SuccinctStaking(STAKING).staked(STAKER_1);
        assertApproxEqAbs(
            stakedAfterFirstReward,
            initialStaked + stakerReward,
            1,
            "Staked amount should increase by staker reward portion"
        );

        // Get shares before unstake
        uint256 stPROVEBalance = IERC20(STAKING).balanceOf(STAKER_1);

        // Unstake from Alice prover - burns stPROVE and escrows iPROVE
        _requestUnstake(STAKER_1, stPROVEBalance);

        // Get escrowed amount (includes first reward)
        uint256 iPROVEEscrowed = ISuccinctStaking(STAKING).unstakeRequests(STAKER_1)[0].iPROVEEscrow;

        // Add more rewards while tokens are in escrow (staker won't get these)
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Withdraw the second reward
        (uint256 protocolFee2, uint256 stakerReward2, uint256 ownerReward2) =
            _calculateFullRewardSplit(rewardAmount);
        _withdrawFromVApp(TREASURY, protocolFee2);
        _withdrawFromVApp(ALICE, ownerReward2);
        _withdrawFromVApp(ALICE_PROVER, stakerReward2);

        // Skip to allow claiming
        skip(UNSTAKE_PERIOD);

        // Claim unstaked tokens
        uint256 claimedAmount = _finishUnstake(STAKER_1);

        // With new implementation, staker gets exactly what was escrowed
        assertApproxEqAbs(
            claimedAmount,
            IERC4626(I_PROVE).previewRedeem(iPROVEEscrowed),
            1,
            "Claimed amount should match escrowed iPROVE converted to PROVE"
        );

        // This should equal initial stake + first reward only
        assertApproxEqAbs(
            claimedAmount,
            stakeAmount + stakerReward,
            1,
            "Should only include rewards earned before unstake request"
        );

        // Prover gets the second reward
        assertApproxEqAbs(
            IERC20(I_PROVE).balanceOf(ALICE_PROVER),
            stakerReward2,
            1,
            "Prover should have second reward"
        );
    }

    function test_Unstake_WhenManySmallUnstakes() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 totalReceived = 0;

        // Test multiple stake/unstake cycles
        uint256 numCycles = 3;

        for (uint256 cycle = 0; cycle < numCycles; cycle++) {
            // Stake some tokens
            uint256 cycleStake = stakeAmount / numCycles;
            deal(PROVE, STAKER_1, cycleStake);
            _stake(STAKER_1, ALICE_PROVER, cycleStake);

            // Get current stPROVE balance
            uint256 stPROVEBalance = IERC20(STAKING).balanceOf(STAKER_1);

            // With new implementation, can only unstake up to available balance
            // Request unstake for the full balance of this cycle
            _requestUnstake(STAKER_1, stPROVEBalance);

            // Verify state after unstake request
            assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0, "stPROVE should be burned");
            assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), stPROVEBalance);

            // Wait and finish this unstake before next cycle
            skip(UNSTAKE_PERIOD);
            uint256 received = _finishUnstake(STAKER_1);
            totalReceived += received;

            // Verify unstake completed
            assertEq(received, cycleStake, "Should receive cycle stake amount");
            assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0, "No pending unstakes");
        }

        // Verify total received (allow for rounding dust)
        assertApproxEqAbs(
            totalReceived,
            stakeAmount,
            numCycles,
            "Should receive approximately total staked amount"
        );
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0, "All stPROVE should be unstaked");

        // Verify escrow is cleared
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(pool.iPROVEEscrow, 0, "Escrow should be cleared");

        // Verify no pending unstakes
        assertEq(
            ISuccinctStaking(STAKING).unstakeRequests(STAKER_1).length,
            0,
            "No pending unstakes should remain"
        );
    }

    function test_Unstake_WhenManySmallStakesUnstakes() public {
        uint256 numStakes = 10;
        uint256 stakeAmountPerCall = STAKER_PROVE_AMOUNT / numStakes;
        uint256 totalStaked = 0;

        // Stake some tokens to Alice prover, across multiple stake calls
        for (uint256 i = 0; i < numStakes; i++) {
            _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmountPerCall);
            totalStaked += stakeAmountPerCall;
        }

        // Verify total staked
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), totalStaked, "Total stPROVE balance");
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), totalStaked, "Total staked amount");

        // With new implementation, we can only unstake up to our balance
        // and validation prevents multiple pending unstakes
        // So we'll unstake all at once
        _requestUnstake(STAKER_1, totalStaked);

        // Verify all unstaked
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0, "All stPROVE should be burned");
        assertEq(
            SuccinctStaking(STAKING).unstakePending(STAKER_1), totalStaked, "Total pending unstake"
        );

        // Wait for the unstake period to pass
        skip(UNSTAKE_PERIOD);

        // Claim the unstake
        uint256 proveReceived = _finishUnstake(STAKER_1);

        assertEq(proveReceived, totalStaked, "Should receive all unstaked");
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), totalStaked, "Final PROVE balance");

        // Verify escrow is cleared
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(pool.iPROVEEscrow, 0, "Escrow should be cleared");
    }

    function test_Unstake_WhenManySmallStakesUnstakesTimeBetween() public {
        uint256 numStakes = 10;
        uint256 stakeAmountPerCall = STAKER_PROVE_AMOUNT / numStakes;
        uint256 timeBetweenStakes = 1 days;
        uint256 totalStaked = 0;

        // Stake some tokens to Alice prover, across multiple stake calls
        for (uint256 i = 0; i < numStakes; i++) {
            _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmountPerCall);
            totalStaked += stakeAmountPerCall;
            skip(timeBetweenStakes);
        }

        // Verify total staked
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), totalStaked, "Total stPROVE balance");
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), totalStaked, "Total staked amount");

        // With new implementation, can only unstake what we have
        // Request unstake for the full balance
        _requestUnstake(STAKER_1, totalStaked);

        // Verify all unstaked
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0, "All stPROVE should be burned");
        assertEq(
            SuccinctStaking(STAKING).unstakePending(STAKER_1), totalStaked, "Total pending unstake"
        );

        // Wait for the unstake period to pass
        skip(UNSTAKE_PERIOD);

        // Claim the unstake
        uint256 proveReceived = _finishUnstake(STAKER_1);

        assertEq(proveReceived, totalStaked, "Should receive all unstaked");
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), totalStaked, "Final PROVE balance");

        // Verify escrow is cleared
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(pool.iPROVEEscrow, 0, "Escrow should be cleared");
    }

    // Test that you can add more unstake claims as long as you have the $stPROVE balance
    function test_Unstake_WhenMultipleRequestsSumToFull() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount1 = stakeAmount * 8 / 10;
        uint256 unstakeAmount2 = stakeAmount - unstakeAmount1;

        // Stake all tokens
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // First partial unstake for some subset of the stake
        _requestUnstake(STAKER_1, unstakeAmount1);

        // Second request for the remaining stake
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(unstakeAmount2);
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

    function test_RevertUnstake_WhenTooManyUnstakeRequests() public {
        uint256 maxRequests = SuccinctStaking(STAKING).maxUnstakeRequests();
        // Stake a large amount to ensure we have enough for all requests
        uint256 stakeAmount = STAKER_PROVE_AMOUNT * 10;
        uint256 unstakeAmountPerRequest = MIN_STAKE_AMOUNT; // Use minimum amount for each request

        // Deal more PROVE to staker
        deal(PROVE, STAKER_1, stakeAmount);

        // Stake tokens to Alice prover
        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, stakeAmount);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);

        // Create the maximum allowed unstake requests
        for (uint256 i = 0; i < maxRequests; i++) {
            vm.prank(STAKER_1);
            SuccinctStaking(STAKING).requestUnstake(unstakeAmountPerRequest);
        }

        // Verify we've hit the max
        assertEq(ISuccinctStaking(STAKING).unstakeRequests(STAKER_1).length, maxRequests);

        // The next request should revert
        vm.expectRevert(ISuccinctStaking.TooManyUnstakeRequests.selector);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(unstakeAmountPerRequest);
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
        // Staker 1 stakes with Alice prover
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Staker 2 also stakes (so prover has some vault balance for slashing)
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Staker 1 requests unstake (burns stPROVE, escrows iPROVE)
        uint256 staker1Shares = IERC20(STAKING).balanceOf(STAKER_1);
        vm.prank(STAKER_1);
        ISuccinctStaking(STAKING).requestUnstake(staker1Shares);

        // Get the escrowed amount and initial escrow pool state
        uint256 iPROVEEscrowed = ISuccinctStaking(STAKING).unstakeRequests(STAKER_1)[0].iPROVEEscrow;
        uint256 slashFactor = ISuccinctStaking(STAKING).unstakeRequests(STAKER_1)[0].slashFactor;
        ISuccinctStaking.EscrowPool memory poolBefore =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);

        assertEq(poolBefore.iPROVEEscrow, iPROVEEscrowed, "Escrow should match unstake request");
        assertEq(poolBefore.slashFactor, SCALAR, "Initial slash factor should be 1e27");
        assertEq(slashFactor, SCALAR, "Snapshot should capture initial factor");

        // During unstake period, request a 50% slash of total stake
        // Total stake = vault (staker2) + escrow (staker1) = 2 * stakeAmount
        uint256 totalStake = stakeAmount * 2;
        uint256 slashAmount = totalStake / 2; // 50% of total
        vm.prank(OWNER);
        MockVApp(VAPP).processSlash(ALICE_PROVER, slashAmount);

        // Process the slash immediately
        vm.prank(OWNER);
        ISuccinctStaking(STAKING).finishSlash(ALICE_PROVER, 0);

        // Check escrow pool after slash
        ISuccinctStaking.EscrowPool memory poolAfter =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        // With pro-rata split, half of the slash should come from escrow
        assertEq(poolAfter.iPROVEEscrow, iPROVEEscrowed / 2, "Escrow should be reduced by 50%");
        assertEq(poolAfter.slashFactor, SCALAR / 2, "Slash factor should be 0.5e27 after 50% slash");

        // After unstake period, finish unstake for Staker 1
        skip(UNSTAKE_PERIOD);

        vm.prank(STAKER_1);
        uint256 proveReceived = ISuccinctStaking(STAKING).finishUnstake(STAKER_1);

        // Staker should receive ~50% due to slash factor
        assertApproxEqAbs(proveReceived, stakeAmount / 2, 2, "Should receive ~50% after 50% slash");

        // Verify escrow is cleared for Staker 1's unstake
        ISuccinctStaking.EscrowPool memory poolFinal =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(poolFinal.iPROVEEscrow, 0, "Escrow should be cleared");

        // Verify Staker 2 also lost 50% of their stake in the vault
        assertApproxEqAbs(
            SuccinctStaking(STAKING).staked(STAKER_2),
            stakeAmount / 2,
            2,
            "Staker 2 should have 50% remaining"
        );
    }

    function test_Unstake_WhenRewardDuringUnstakePeriod() public {
        // Staker stakes with Alice prover.
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Alice prover earns rewards before unstake request.
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        // Withdraw rewards to increase prover assets.
        (uint256 protocolFee, uint256 stakerReward, uint256 ownerReward) =
            _calculateFullRewardSplit(STAKER_PROVE_AMOUNT / 2);
        _withdrawFromVApp(TREASURY, protocolFee);
        _withdrawFromVApp(ALICE, ownerReward);
        _withdrawFromVApp(ALICE_PROVER, stakerReward);

        // Get staked amount after rewards (includes rewards earned before unstake)
        uint256 stakedBeforeUnstake = SuccinctStaking(STAKING).staked(STAKER_1);
        assertApproxEqAbs(
            stakedBeforeUnstake, stakeAmount + stakerReward, 1, "Staked should include rewards"
        );

        // Request unstake for the full balance (burns stPROVE and escrows iPROVE)
        uint256 stPROVEBalance = IERC20(STAKING).balanceOf(STAKER_1);
        vm.prank(STAKER_1);
        ISuccinctStaking(STAKING).requestUnstake(stPROVEBalance);

        // Get the escrowed iPROVE amount from the unstake request
        uint256 iPROVEEscrowed = ISuccinctStaking(STAKING).unstakeRequests(STAKER_1)[0].iPROVEEscrow;

        // Verify escrow pool contains the iPROVE
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(pool.iPROVEEscrow, iPROVEEscrowed, "Escrow should contain unstaked iPROVE");
        assertEq(pool.slashFactor, SCALAR, "Slash factor should be 1e27");

        // More rewards are earned during unstaking period (but unstaker won't get these)
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, STAKER_PROVE_AMOUNT / 4);
        (uint256 protocolFee2, uint256 stakerReward2, uint256 ownerReward2) =
            _calculateFullRewardSplit(STAKER_PROVE_AMOUNT / 4);
        _withdrawFromVApp(TREASURY, protocolFee2);
        _withdrawFromVApp(ALICE, ownerReward2);
        _withdrawFromVApp(ALICE_PROVER, stakerReward2);

        // Skip to end of unstake period
        skip(UNSTAKE_PERIOD);

        // Finish unstake
        vm.prank(STAKER_1);
        uint256 proveReceived = ISuccinctStaking(STAKING).finishUnstake(STAKER_1);

        // With new implementation, staker receives exactly what was escrowed
        // (converted to PROVE), not affected by rewards during unstaking
        assertApproxEqAbs(
            proveReceived,
            IERC4626(I_PROVE).previewRedeem(iPROVEEscrowed),
            1,
            "Staker should receive PROVE based on escrowed iPROVE"
        );

        // Verify rewards earned during unstaking stayed in the prover
        // Since no other stakers, the prover should have all the rewards from the second fulfillment
        assertApproxEqAbs(
            IERC20(I_PROVE).balanceOf(ALICE_PROVER),
            stakerReward2,
            2,
            "Prover should retain rewards earned during unstaking"
        );

        // Verify escrow is cleared
        ISuccinctStaking.EscrowPool memory poolAfter =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(poolAfter.iPROVEEscrow, 0, "Escrow should be cleared");
        assertEq(IERC20(I_PROVE).balanceOf(STAKING), 0, "Staking contract should have no iPROVE");
    }

    // Rewards added when an unstake is in-progress go only to remaining stakers
    function test_Unstake_WhenRewardDuringOngoingUnstake() public {
        // Staker 1 and 2 stake with Alice prover
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Staker 1 requests unstake (burns stPROVE, escrows iPROVE)
        uint256 staker1Shares = IERC20(STAKING).balanceOf(STAKER_1);
        vm.prank(STAKER_1);
        ISuccinctStaking(STAKING).requestUnstake(staker1Shares);

        uint256 staker1Escrowed =
            ISuccinctStaking(STAKING).unstakeRequests(STAKER_1)[0].iPROVEEscrow;

        // After Staker 1 unstakes, only Staker 2 remains staked
        // Rewards paid out now should go entirely to Staker 2
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);
        (, uint256 stakerReward,) = _calculateFullRewardSplit(STAKER_PROVE_AMOUNT / 2);
        _withdrawFromVApp(ALICE_PROVER, stakerReward);

        // Staker 2 requests unstake after receiving rewards
        uint256 staker2Shares = IERC20(STAKING).balanceOf(STAKER_2);
        vm.prank(STAKER_2);
        ISuccinctStaking(STAKING).requestUnstake(staker2Shares);

        uint256 staker2Escrowed =
            ISuccinctStaking(STAKING).unstakeRequests(STAKER_2)[0].iPROVEEscrow;

        // Staker 1 finishes unstaking
        skip(UNSTAKE_PERIOD);
        vm.prank(STAKER_1);
        uint256 proveReceived1 = ISuccinctStaking(STAKING).finishUnstake(STAKER_1);

        // Staker 1 receives exactly what was escrowed (no rewards during unstaking)
        assertApproxEqAbs(
            proveReceived1,
            IERC4626(I_PROVE).previewRedeem(staker1Escrowed),
            1,
            "Staker 1 should receive only escrowed amount"
        );
        assertApproxEqAbs(proveReceived1, stakeAmount, 1, "Staker 1 gets original stake");

        // Staker 2 finishes unstaking
        vm.prank(STAKER_2);
        uint256 proveReceived2 = ISuccinctStaking(STAKING).finishUnstake(STAKER_2);

        // Staker 2 should receive original stake + full reward
        assertApproxEqAbs(
            proveReceived2,
            IERC4626(I_PROVE).previewRedeem(staker2Escrowed),
            2,
            "Staker 2 should receive escrowed amount including rewards"
        );
        assertApproxEqAbs(
            proveReceived2,
            stakeAmount + stakerReward,
            2,
            "Staker 2 gets original stake + full reward"
        );

        // No iPROVE should remain (allow 1 wei rounding dust)
        assertLe(
            IERC20(I_PROVE).balanceOf(ALICE_PROVER),
            1,
            "Prover should have at most 1 wei iPROVE dust"
        );
        assertEq(IERC20(I_PROVE).balanceOf(STAKING), 0, "Staking contract should have no iPROVE");
    }

    // Same as above but with staker 2 finishing the unstake first
    function test_Unstake_WhenRewardDuringOngoingUnstakeOutOfOrder() public {
        // Staker 1 and 2 stake with Alice prover
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Staker 1 requests unstake (burns stPROVE, escrows iPROVE)
        uint256 staker1Shares = IERC20(STAKING).balanceOf(STAKER_1);
        vm.prank(STAKER_1);
        ISuccinctStaking(STAKING).requestUnstake(staker1Shares);

        uint256 staker1Escrowed =
            ISuccinctStaking(STAKING).unstakeRequests(STAKER_1)[0].iPROVEEscrow;

        // After Staker 1 unstakes, only Staker 2 remains staked
        // Rewards paid out now should go entirely to Staker 2
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);
        (, uint256 stakerReward,) = _calculateFullRewardSplit(STAKER_PROVE_AMOUNT / 2);
        _withdrawFromVApp(ALICE_PROVER, stakerReward);

        // Staker 2 requests unstake after receiving rewards
        uint256 staker2Shares = IERC20(STAKING).balanceOf(STAKER_2);
        vm.prank(STAKER_2);
        ISuccinctStaking(STAKING).requestUnstake(staker2Shares);

        uint256 staker2Escrowed =
            ISuccinctStaking(STAKING).unstakeRequests(STAKER_2)[0].iPROVEEscrow;

        // Staker 2 finishes unstaking first (out of order)
        skip(UNSTAKE_PERIOD);
        vm.prank(STAKER_2);
        uint256 proveReceived2 = ISuccinctStaking(STAKING).finishUnstake(STAKER_2);

        // Staker 2 should receive original stake + full reward
        assertApproxEqAbs(
            proveReceived2,
            IERC4626(I_PROVE).previewRedeem(staker2Escrowed),
            2,
            "Staker 2 should receive escrowed amount including rewards"
        );
        assertApproxEqAbs(
            proveReceived2,
            stakeAmount + stakerReward,
            2,
            "Staker 2 gets original stake + full reward"
        );

        // Staker 1 finishes unstaking second
        vm.prank(STAKER_1);
        uint256 proveReceived1 = ISuccinctStaking(STAKING).finishUnstake(STAKER_1);

        // Staker 1 receives exactly what was escrowed (no rewards during unstaking)
        assertApproxEqAbs(
            proveReceived1,
            IERC4626(I_PROVE).previewRedeem(staker1Escrowed),
            1,
            "Staker 1 should receive only escrowed amount"
        );
        assertApproxEqAbs(proveReceived1, stakeAmount, 1, "Staker 1 gets original stake");

        // No iPROVE should remain (allow 1 wei rounding dust)
        assertLe(
            IERC20(I_PROVE).balanceOf(ALICE_PROVER),
            1,
            "Prover should have at most 1 wei iPROVE dust"
        );
        assertEq(IERC20(I_PROVE).balanceOf(STAKING), 0, "Staking contract should have no iPROVE");
    }

    // Test interleaving: new unstake requests after slash with snapshot factor verification
    function test_Unstake_WhenRequestAfterSlash() public {
        // Define all test values at the start, derived from setUp constants
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2; // Use half of standard amount for cleaner math
        uint256 firstSlashAmount = stakeAmount * 60 / 100; // 60% slash
        uint256 totalAfterB = (stakeAmount - firstSlashAmount) + stakeAmount; // 40 + 100 = 140
        uint256 secondSlashAmount = totalAfterB / 2; // 50% of remaining total

        // Staker A stakes and requests unstake (snapshot F₀ = 1e27)
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _requestUnstake(STAKER_1, stakeAmount);

        // Verify A's unstake request has snapshot factor of 1e27
        assertEq(
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1).length,
            1,
            "Staker A should have 1 unstake request"
        );
        assertEq(
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1)[0].slashFactor,
            1e27,
            "A's snapshot should be 1e27"
        );

        // First slash: 60% of initial stake
        _completeSlash(ALICE_PROVER, firstSlashAmount);
        // Factor = 0.4e27 after 60% slash
        uint256 firstFactor = SCALAR * (stakeAmount - firstSlashAmount) / stakeAmount;
        assertEq(
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER).slashFactor,
            firstFactor,
            "Slash factor should reflect remaining ratio"
        );

        // Staker B stakes same amount, requests unstake (snapshot at current factor)
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);
        _requestUnstake(STAKER_2, stakeAmount);

        // Verify B's unstake request has snapshot factor of 0.4e27
        assertEq(
            SuccinctStaking(STAKING).unstakeRequests(STAKER_2).length,
            1,
            "Staker B should have 1 unstake request"
        );
        assertEq(
            SuccinctStaking(STAKING).unstakeRequests(STAKER_2)[0].slashFactor,
            firstFactor,
            "B's snapshot should match pool factor after first slash"
        );

        // Second slash: 50% of remaining total
        _completeSlash(ALICE_PROVER, secondSlashAmount);
        // Factor compounds: previous factor * remaining / total
        uint256 finalFactor = firstFactor * (totalAfterB - secondSlashAmount) / totalAfterB;
        assertEq(
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER).slashFactor,
            finalFactor,
            "Slash factor should compound correctly"
        );

        // Wait for unstake period
        skip(UNSTAKE_PERIOD);

        // Finish unstakes and verify amounts
        uint256 balanceA = IERC20(PROVE).balanceOf(STAKER_1);
        uint256 balanceB = IERC20(PROVE).balanceOf(STAKER_2);

        uint256 receivedA = _finishUnstake(STAKER_1);
        uint256 receivedB = _finishUnstake(STAKER_2);

        // A should receive: stakeAmount * currentFactor / snapshotFactor = stakeAmount * 0.2 / 1.0
        assertEq(
            receivedA,
            stakeAmount * finalFactor / SCALAR,
            "Staker A should receive proportional to factor change"
        );
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1) - balanceA,
            receivedA,
            "A's balance should increase correctly"
        );

        // B should receive: stakeAmount * currentFactor / snapshotFactor = stakeAmount * 0.2 / 0.4
        assertEq(
            receivedB,
            stakeAmount * finalFactor / firstFactor,
            "Staker B should receive proportional to factor change"
        );
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_2) - balanceB,
            receivedB,
            "B's balance should increase correctly"
        );

        // Verify that both stakers received different percentages due to different snapshot factors
        // A: 20% of original stake (due to 1.0 snapshot factor)
        // B: 50% of original stake (due to 0.4 snapshot factor)
        // This proves the snapshot logic works correctly
    }

    // Two claims, wait until only the first matures, verify second remains intact.
    function test_Unstake_WhenTwoClaimsMixedReady() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 firstClaim = stakeAmount / 4; // Use smaller amounts so both can coexist
        uint256 secondClaim = stakeAmount / 4;

        // Stake tokens
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Create first unstake request
        _requestUnstake(STAKER_1, firstClaim);

        // Wait half the unstake period
        skip(UNSTAKE_PERIOD / 2);

        // Create second unstake request (will mature later)
        _requestUnstake(STAKER_1, secondClaim);

        // Verify we have 2 claims
        SuccinctStaking.UnstakeClaim[] memory claimsBefore =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        assertEq(claimsBefore.length, 2, "Should have 2 claims");

        // Wait until only first claim is ready
        skip(UNSTAKE_PERIOD / 2 + 1); // Now first is ready, second is not

        // Call finishUnstake
        uint256 received = _finishUnstake(STAKER_1);

        // Should receive only the first claim
        assertEq(received, firstClaim, "Should receive only first claim");

        // Verify second claim remains intact
        SuccinctStaking.UnstakeClaim[] memory claimsAfter =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        assertEq(claimsAfter.length, 1, "Should have 1 claim remaining");

        // Wait for second claim and finish
        skip(UNSTAKE_PERIOD / 2);
        uint256 receivedSecond = _finishUnstake(STAKER_1);
        assertEq(receivedSecond, secondClaim, "Should receive second claim");

        // All claims processed
        assertEq(
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1).length, 0, "No claims should remain"
        );
    }

    // Test finishUnstake() when some claims are ready and others are not
    function test_Unstake_WhenSomeClaimsReadyOthersNot() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT * 2; // Stake double amount to support multiple requests
        uint256 unstakeAmountPerRequest = MIN_STAKE_AMOUNT; // Use minimum amount for each request

        // Stake tokens
        deal(PROVE, STAKER_1, stakeAmount);
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Create multiple unstake requests at different times
        uint256[] memory requestTimestamps = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            _requestUnstake(STAKER_1, unstakeAmountPerRequest);
            requestTimestamps[i] = block.timestamp;

            // Skip different amounts of time between requests
            if (i < 4) {
                skip(UNSTAKE_PERIOD / 4); // Each request is 1/4 period apart
            }
        }

        // At this point:
        // - Request 0: Created at t=0, ready at t=UNSTAKE_PERIOD
        // - Request 1: Created at t=UNSTAKE_PERIOD/4, ready at t=5*UNSTAKE_PERIOD/4
        // - Request 2: Created at t=UNSTAKE_PERIOD/2, ready at t=3*UNSTAKE_PERIOD/2
        // - Request 3: Created at t=3*UNSTAKE_PERIOD/4, ready at t=7*UNSTAKE_PERIOD/4
        // - Request 4: Created at t=UNSTAKE_PERIOD, ready at t=2*UNSTAKE_PERIOD

        // Move forward to when only the first 3 requests are ready
        skip(UNSTAKE_PERIOD / 2); // Now at t = 3*UNSTAKE_PERIOD/2

        // Check claims before finishing
        SuccinctStaking.UnstakeClaim[] memory claimsBefore =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        assertEq(claimsBefore.length, 5, "Should have 5 claims before finishing");

        // Get initial balance
        uint256 balanceBefore = IERC20(PROVE).balanceOf(STAKER_1);

        // Finish unstake - should only process first 3 claims
        uint256 received = _finishUnstake(STAKER_1);

        // Check claims after finishing
        SuccinctStaking.UnstakeClaim[] memory claimsAfter =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        assertEq(claimsAfter.length, 2, "Should have 2 claims remaining");

        // Verify amount received (3 claims worth)
        assertEq(received, unstakeAmountPerRequest * 3, "Should receive 3 claims worth");
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1) - balanceBefore,
            unstakeAmountPerRequest * 3,
            "Balance should increase by 3 claims worth"
        );

        // Verify remaining claims are the non-ready ones
        // Due to swap-and-pop behavior, the order might be different
        // But the total pending should be 2 claims worth
        assertEq(
            SuccinctStaking(STAKING).unstakePending(STAKER_1),
            unstakeAmountPerRequest * 2,
            "Should have 2 claims worth pending"
        );

        // Wait for remaining claims to be ready
        skip(UNSTAKE_PERIOD);

        // Finish remaining claims
        uint256 receivedFinal = _finishUnstake(STAKER_1);
        assertEq(receivedFinal, unstakeAmountPerRequest * 2, "Should receive remaining 2 claims");

        // All claims should be processed now
        SuccinctStaking.UnstakeClaim[] memory claimsFinal =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        assertEq(claimsFinal.length, 0, "All claims should be processed");

        // Verify total received equals 5 * unstakeAmountPerRequest
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1),
            unstakeAmountPerRequest * 5,
            "Should receive all 5 unstake claims"
        );
    }

    // Test too-many-requests counter reset when all requests are finished
    function test_Unstake_WhenMaxRequestsReset() public {
        // Get the actual max requests from the contract
        uint256 maxRequests = SuccinctStaking(STAKING).maxUnstakeRequests();
        // Use minimum stake amount to maximize number of requests we can make
        uint256 requestAmount = MIN_STAKE_AMOUNT;
        // Need enough for all requests + pending claims validation + one extra request
        // Using a large multiplier to ensure we have enough
        uint256 stakeAmount = requestAmount * (maxRequests * 2 + 10);

        // Give staker enough tokens
        deal(PROVE, STAKER_1, stakeAmount);
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Create max requests
        for (uint256 i = 0; i < maxRequests; i++) {
            _requestUnstake(STAKER_1, requestAmount);
        }

        // Verify we have max requests
        SuccinctStaking.UnstakeClaim[] memory requests =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        assertEq(requests.length, maxRequests, "Should have max unstake requests");

        // Should revert on next request with TooManyUnstakeRequests
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.TooManyUnstakeRequests.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(MIN_STAKE_AMOUNT);

        // Wait for unstake period
        skip(UNSTAKE_PERIOD);

        // Finish all requests with a single call (finishUnstake processes all ready claims)
        _finishUnstake(STAKER_1);

        // Verify all requests are finished (length should be 0)
        SuccinctStaking.UnstakeClaim[] memory requestsAfter =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        assertEq(requestsAfter.length, 0, "All requests should be finished");

        // Give staker more tokens for new requests
        // Need enough to create maxRequests again
        uint256 newStakeAmount = requestAmount * (maxRequests + 1);
        deal(PROVE, STAKER_1, newStakeAmount);
        _stake(STAKER_1, ALICE_PROVER, newStakeAmount);

        // Should be able to create new request immediately (counter reset)
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(requestAmount); // Should not revert

        // Verify new request was created
        SuccinctStaking.UnstakeClaim[] memory newRequests =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        assertEq(newRequests.length, 1, "Should have 1 new unstake request");

        // Create more requests up to max - 1 (since we already created one)
        for (uint256 i = 1; i < maxRequests; i++) {
            vm.prank(STAKER_1);
            SuccinctStaking(STAKING).requestUnstake(requestAmount);
        }

        // Verify we have max requests again
        SuccinctStaking.UnstakeClaim[] memory finalRequests =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        assertEq(finalRequests.length, maxRequests, "Should have max requests again");

        // Should revert on exceeding max again
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.TooManyUnstakeRequests.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(requestAmount);
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Unstake_PartialAmount(uint256 _unstakeAmount) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 unstakeAmount = bound(_unstakeAmount, 1, stakeAmount);

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Get stPROVE balance before unstake
        uint256 stPROVEBefore = IERC20(STAKING).balanceOf(STAKER_1);

        // Request partial unstake (burns stPROVE immediately)
        _requestUnstake(STAKER_1, unstakeAmount);

        // Check that unstake pending matches requested amount
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), unstakeAmount);

        // Check that stPROVE was burned and staked amount reduced
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stPROVEBefore - unstakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount - unstakeAmount);

        // Check escrow contains the unstaked amount
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(pool.iPROVEEscrow, unstakeAmount);

        // Wait and complete unstake
        skip(UNSTAKE_PERIOD);
        uint256 receivedAmount = _finishUnstake(STAKER_1);

        // Verify amounts
        assertEq(receivedAmount, unstakeAmount);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount - unstakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount - unstakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), unstakeAmount);

        // Verify escrow is cleared
        pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(pool.iPROVEEscrow, 0);
    }

    function testFuzz_Unstake_WithDispenseRewards(uint256 _dispenseAmount, uint256 _unstakeAmount)
        public
    {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 dispenseAmount = bound(_dispenseAmount, 1000, 1_000_000e18);

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Get initial stPROVE balance (shares)
        uint256 stPROVEBalance = IERC20(STAKING).balanceOf(STAKER_1);
        assertEq(stPROVEBalance, stakeAmount, "Initial stPROVE should equal stake amount");

        // Dispense rewards
        _dispense(dispenseAmount);

        // Get staked amount after dispense (PROVE value increased, but shares stay same)
        uint256 stakedAfterDispense = SuccinctStaking(STAKING).staked(STAKER_1);
        assertApproxEqAbs(stakedAfterDispense, stakeAmount + dispenseAmount, 10);
        assertEq(
            IERC20(STAKING).balanceOf(STAKER_1), stPROVEBalance, "stPROVE shares should not change"
        );

        // Bound unstake amount to shares we have
        uint256 unstakeShares = bound(_unstakeAmount, 1, stPROVEBalance);

        // Request unstake (using shares)
        _requestUnstake(STAKER_1, unstakeShares);

        // Complete unstake
        skip(UNSTAKE_PERIOD);
        uint256 receivedAmount = _finishUnstake(STAKER_1);

        // Should receive proportional share of the total value
        uint256 expectedReceived = (unstakeShares * stakedAfterDispense) / stPROVEBalance;
        assertApproxEqAbs(receivedAmount, expectedReceived, 10);
    }

    function testFuzz_Unstake_MultipleRequests(uint256[3] memory _amounts) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // With new implementation, can only create one unstake request at a time
        // So we'll test multiple cycles of stake/unstake instead
        uint256 totalReceived = 0;
        uint256 initialBalance = IERC20(PROVE).balanceOf(STAKER_1);

        for (uint256 i = 0; i < _amounts.length; i++) {
            // Bound each stake/unstake amount
            _amounts[i] = bound(_amounts[i], MIN_STAKE_AMOUNT, stakeAmount / 3);

            // Give staker more PROVE for this cycle
            uint256 currentBalance = IERC20(PROVE).balanceOf(STAKER_1);
            deal(PROVE, STAKER_1, currentBalance + _amounts[i]);

            // Stake
            _stake(STAKER_1, ALICE_PROVER, _amounts[i]);

            // Get balance and unstake all
            uint256 balance = SuccinctStaking(STAKING).balanceOf(STAKER_1);
            _requestUnstake(STAKER_1, balance);

            // Wait and finish
            skip(UNSTAKE_PERIOD);
            uint256 received = _finishUnstake(STAKER_1);
            totalReceived += received;

            // Verify cycle completed correctly
            assertEq(received, _amounts[i]);
            assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
            assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        }

        // Verify total
        uint256 totalStaked = _amounts[0] + _amounts[1] + _amounts[2];
        assertEq(totalReceived, totalStaked);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), initialBalance + totalStaked);
    }

    function testFuzz_Unstake_WithSlashDuringUnstakePeriod(uint256 _slashAmount) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Need two stakers so prover has both vault and escrow balance
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Staker 1 requests unstake (creates escrow)
        _requestUnstake(STAKER_1, stakeAmount);

        // Now we have:
        // - Vault: stakeAmount (from STAKER_2)
        // - Escrow: stakeAmount (from STAKER_1)
        // - Total: 2 * stakeAmount

        // Bound slash to at most total stake
        uint256 totalStake = stakeAmount * 2;
        uint256 slashAmount = bound(_slashAmount, 1, totalStake);

        // With the fix, slashes can now exceed vault balance up to total (vault + escrow)
        uint256 actualSlashAmount = slashAmount > totalStake ? totalStake : slashAmount;

        // Request and execute slash
        _requestSlash(ALICE_PROVER, slashAmount);
        _finishSlash(ALICE_PROVER, 0);

        // Complete unstake after slash
        skip(UNSTAKE_PERIOD);
        uint256 receivedAmount = _finishUnstake(STAKER_1);

        // The slash is distributed pro-rata between vault and escrow
        // Escrow gets: actualSlashAmount * escrowBalance / totalStake
        // Since escrow and vault are equal, escrow loses half of actualSlashAmount
        uint256 escrowSlashed = Math.mulDiv(actualSlashAmount, stakeAmount, totalStake);
        uint256 expectedAmount = IERC4626(I_PROVE).previewRedeem(stakeAmount - escrowSlashed);

        assertApproxEqAbs(receivedAmount, expectedAmount, 10);
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
    }

    // Various request counts and slash scenarios have correct balance changes.
    function testFuzz_UnstakePending_CorrectnessWithMaxRequests(uint256 _seed) public {
        vm.assume(_seed > 0);

        uint256 stakeAmount = STAKER_PROVE_AMOUNT * 2;
        deal(PROVE, STAKER_1, stakeAmount);
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Create variable number of requests (1-MAX_UNSTAKE_REQUESTS)
        uint256 numRequests = (_seed % MAX_UNSTAKE_REQUESTS) + 1;
        // Use smaller divisor to ensure we have enough balance even with slashing
        uint256 baseRequestAmount = stakeAmount / (numRequests * 3); // More conservative

        // Ensure base amount is at least MIN_STAKE_AMOUNT
        if (baseRequestAmount < MIN_STAKE_AMOUNT) {
            baseRequestAmount = MIN_STAKE_AMOUNT;
            // Adjust numRequests if needed to ensure we don't exceed stake
            uint256 maxRequests = stakeAmount / (MIN_STAKE_AMOUNT * 2);
            if (numRequests > maxRequests && maxRequests > 0) {
                numRequests = maxRequests;
            }
        }

        for (uint256 i = 0; i < numRequests; i++) {
            uint256 variableAmount =
                baseRequestAmount >= 4 ? ((_seed >> (i * 4)) % (baseRequestAmount / 4)) : 0;
            uint256 requestAmount = baseRequestAmount + variableAmount;

            // Ensure we don't try to unstake more than available balance
            uint256 availableBalance = SuccinctStaking(STAKING).balanceOf(STAKER_1);

            if (requestAmount > availableBalance) {
                requestAmount = availableBalance;
            }

            // Skip if no balance left or if request is too small
            if (requestAmount == 0 || requestAmount < MIN_STAKE_AMOUNT) {
                break;
            }

            _requestUnstake(STAKER_1, requestAmount);

            // Random slash after some requests
            if (i > 0 && (_seed >> (i * 8)) % 3 == 0) {
                // Simplified slash calculation to avoid stack too deep
                uint256 currentStaked = SuccinctStaking(STAKING).proverStaked(ALICE_PROVER);
                if (currentStaked > 0) {
                    uint256 slashAmount = currentStaked / 4; // Simple 25% slash
                    _completeSlash(ALICE_PROVER, slashAmount);
                }
            }
        }

        // Get actual pending from contract
        uint256 actualPending = SuccinctStaking(STAKING).unstakePending(STAKER_1);

        // Calculate expected pending manually
        SuccinctStaking.UnstakeClaim[] memory claims =
            SuccinctStaking(STAKING).unstakeRequests(STAKER_1);
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        uint256 currentFactor = pool.slashFactor == 0 ? SCALAR : pool.slashFactor;

        uint256 manualPending = 0;
        for (uint256 i = 0; i < claims.length; i++) {
            uint256 iPROVEScaled =
                Math.mulDiv(claims[i].iPROVEEscrow, currentFactor, claims[i].slashFactor);
            manualPending += IERC4626(I_PROVE).previewRedeem(iPROVEScaled);
        }

        // Allow small rounding differences due to integer division
        assertApproxEqAbs(
            actualPending,
            manualPending,
            claims.length * 2,
            "Pending calculation should match with small tolerance"
        );
    }

    // Tests that any number of unstake requests (up to MAX_UNSTAKE_REQUESTS) can be made as long
    // as they sum to the staked amount.
    function testFuzz_Unstake_MultipleRequestsSumToFull(
        uint256 _seed,
        uint8 _numRequests,
        uint256 _stakeAmount
    ) public {
        // Constrain test parameters
        uint256 maxUnstakeRequests = SuccinctStaking(STAKING).maxUnstakeRequests();
        uint256 numRequests = bound(uint256(_numRequests), 1, maxUnstakeRequests);
        uint256 stakeAmount = bound(_stakeAmount, MIN_STAKE_AMOUNT * numRequests, 1_000_000e18);

        // Stake the tokens
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Get the stPROVE balance before unstake
        uint256 stPROVEOriginalBalance = IERC20(STAKING).balanceOf(STAKER_1);

        // Create a random partition of `remainingShares` that:
        // 1. has length numRequests
        // 2. each part >= MIN_STAKE_AMOUNT
        // 3. parts sum == remainingShares
        uint256[] memory parts = new uint256[](numRequests);
        uint256 remainingShares = stPROVEOriginalBalance;

        for (uint256 i = 0; i < numRequests - 1; i++) {
            // Pseudo-random slice in range [MIN, remaining - MIN*(left-1)]
            uint256 minPart = MIN_STAKE_AMOUNT;
            uint256 maxPart = remainingShares - minPart * (numRequests - 1 - i);
            uint256 sliceRaw = uint256(keccak256(abi.encode(_seed, i)));
            uint256 sliceSize = minPart + (sliceRaw % (maxPart - minPart + 1));

            parts[i] = sliceSize;
            remainingShares -= sliceSize;
        }
        // Last piece is whatever is left
        parts[numRequests - 1] = remainingShares;

        // Randomize the order of unstake requests
        uint256 shuffleKey = uint256(keccak256(abi.encode(_seed, "shuffle")));
        for (uint256 i = 0; i < numRequests; i++) {
            uint256 j = (shuffleKey >> (i * 8)) % numRequests;
            (parts[i], parts[j]) = (parts[j], parts[i]);
        }

        // Perform the unstake requests
        uint256 requestedUnstakeSum;
        for (uint256 i = 0; i < numRequests; i++) {
            requestedUnstakeSum += parts[i];
            _requestUnstake(STAKER_1, parts[i]);

            // stPROVE balance after each request must equal original stPROVE balance - requested unstake sum
            assertEq(
                IERC20(STAKING).balanceOf(STAKER_1), stPROVEOriginalBalance - requestedUnstakeSum
            );
        }

        // After all unstake requests, stPROVE balance should be zero
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0);

        // After all unstake requests, pending unstake should equal the full stake amount
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), stakeAmount);

        // Finish the unstake and get the full stake amount back
        skip(UNSTAKE_PERIOD);
        uint256 received = _finishUnstake(STAKER_1);
        assertEq(received, stakeAmount);
    }

    // Tests that any number of unstake requests (up to MAX_UNSTAKE_REQUESTS) can be made as long
    // as they sum to the staked amount, with time periods between each unstake.
    function testFuzz_Unstake_MultipleRequestsSumToFullWithTimeBetween(
        uint256 _seed,
        uint8 _numRequests,
        uint256 _stakeAmount,
        uint256 _maxTimeBetweenRequests
    ) public {
        // Constrain test parameters
        uint256 maxUnstakeRequests = SuccinctStaking(STAKING).maxUnstakeRequests();
        uint256 numRequests = bound(uint256(_numRequests), 1, maxUnstakeRequests);
        uint256 stakeAmount = bound(_stakeAmount, MIN_STAKE_AMOUNT * numRequests, 1_000_000e18);
        uint256 maxTimeBetweenRequests =
            bound(_maxTimeBetweenRequests, 1, uint256(type(uint32).max));

        // Stake the tokens
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Get the stPROVE balance before unstake
        uint256 stPROVEOriginalBalance = IERC20(STAKING).balanceOf(STAKER_1);

        // Create a random partition of `remainingShares` that:
        // 1. has length numRequests
        // 2. each part >= MIN_STAKE_AMOUNT
        // 3. parts sum == remainingShares
        uint256[] memory parts = new uint256[](numRequests);
        uint256 remainingShares = stPROVEOriginalBalance;

        for (uint256 i = 0; i < numRequests - 1; i++) {
            // Pseudo-random slice in range [MIN, remaining - MIN*(left-1)]
            uint256 minPart = MIN_STAKE_AMOUNT;
            uint256 maxPart = remainingShares - minPart * (numRequests - 1 - i);
            uint256 sliceRaw = uint256(keccak256(abi.encode(_seed, i)));
            uint256 sliceSize = minPart + (sliceRaw % (maxPart - minPart + 1));

            parts[i] = sliceSize;
            remainingShares -= sliceSize;
        }
        // Last piece is whatever is left
        parts[numRequests - 1] = remainingShares;

        // Randomize the order of unstake requests
        uint256 shuffleKey = uint256(keccak256(abi.encode(_seed, "shuffle")));
        for (uint256 i = 0; i < numRequests; i++) {
            uint256 j = (shuffleKey >> (i * 8)) % numRequests;
            (parts[i], parts[j]) = (parts[j], parts[i]);
        }

        // Perform the unstake requests
        uint256 requestedUnstakeSum;
        for (uint256 i = 0; i < numRequests; i++) {
            requestedUnstakeSum += parts[i];
            _requestUnstake(STAKER_1, parts[i]);

            // stPROVE balance after each request must equal original stPROVE balance - requested unstake sum
            assertEq(
                IERC20(STAKING).balanceOf(STAKER_1), stPROVEOriginalBalance - requestedUnstakeSum
            );

            // Skip random time between requests (except after the last one)
            if (i < numRequests - 1) {
                uint256 timeToSkip =
                    uint256(keccak256(abi.encode(_seed, "timeSkip", i))) % maxTimeBetweenRequests;
                skip(timeToSkip);
            }
        }

        // After all unstake requests, stPROVE balance should be zero
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), 0);

        // After all unstake requests, pending unstake should equal the full stake amount
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), stakeAmount);

        // Finish the unstake and get the full stake amount back
        skip(UNSTAKE_PERIOD);
        uint256 received = _finishUnstake(STAKER_1);
        assertEq(received, stakeAmount);
    }
}
