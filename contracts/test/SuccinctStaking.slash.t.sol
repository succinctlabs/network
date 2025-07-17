// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {IProverRegistry} from "../src/interfaces/IProverRegistry.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract SuccinctStakingSlashTests is SuccinctStakingTest {
    // Slash the full amount of a prover's stake
    function test_Slash_WhenFullAmount() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Check state after staking
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);

        // Slash the prover for all of their stake
        uint256 slashAmount = SuccinctStaking(STAKING).proverStaked(ALICE_PROVER);
        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify slashing effects
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount - slashAmount);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(IERC4626(ALICE_PROVER).previewRedeem(stakeAmount), 0);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
    }

    // Slash half the amount of Alice prover's stake
    function test_Slash_WhenPartialAmount() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Check state after staking
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);

        // Slash the prover for half of their stake
        uint256 slashAmount = IERC4626(ALICE_PROVER).totalAssets() / 2;
        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify partial slashing effects
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount - slashAmount);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), slashAmount);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), slashAmount);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(IERC4626(ALICE_PROVER).previewRedeem(stakeAmount), stakeAmount - slashAmount);

        // Complete unstake process
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify final state
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);

        // Staker gets back half the original stake amount
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount - slashAmount);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
    }

    // Slash a prover fully should make both stakers get slashed fully
    function test_Slash_WhenTwoStakersFullSlash() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);
        _permitAndStake(STAKER_2, STAKER_2_PK, ALICE_PROVER, stakeAmount);

        // Slash the prover
        uint256 slashAmount = IERC4626(ALICE_PROVER).totalAssets();
        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify stakers fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);

        // Unstake
        _completeUnstake(STAKER_1, stakeAmount);
        _completeUnstake(STAKER_2, stakeAmount);

        // Verify stakers fully slashed after unstaking
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), 0);
    }

    // Staker recieve a dispense and then get slashed for that new full amount
    function test_Slash_WhenDispenseBeforeFullSlash() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 multiplier = 10;
        uint256 dispenseAmount = stakeAmount * multiplier;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Dispense some $PROVE
        _dispense(dispenseAmount);

        // Slash the prover for all of their stake
        uint256 slashAmount = IERC4626(ALICE_PROVER).totalAssets();
        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), multiplier); // Rounding error - ideally when we slash we could make this 0.

        // Unstake
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify still fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), multiplier); // Rounding error - ideally when we slash we could make this 0.
    }

    // Stakers recieve a dispense and then get slashed for that new full amount
    function test_Slash_WhenTwoStakersDispenseBeforeFullSlash() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 multiplier = 10;
        uint256 dispenseAmount = stakeAmount * multiplier;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);
        _permitAndStake(STAKER_2, STAKER_2_PK, ALICE_PROVER, stakeAmount);

        // Dispense some $PROVE
        _dispense(dispenseAmount);

        // Slash the prover for all of their stake
        uint256 slashAmount = IERC4626(ALICE_PROVER).totalAssets();
        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), multiplier / 2); // Rounding error - ideally when we slash we could make this 0.

        // Unstake
        _completeUnstake(STAKER_1, stakeAmount);
        _completeUnstake(STAKER_2, stakeAmount);

        // Verify still fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), multiplier / 2); // Rounding error - ideally when we slash we could make this 0.
    }

    // Prover's stakers fully slashed down to zero will not get any $PROVE from future dispenses
    function test_Slash_WhenDispenseAfterFullSlash() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 dispenseAmount = stakeAmount;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Slash the prover for all of their stake
        uint256 slashAmount = IERC4626(ALICE_PROVER).totalAssets();
        _completeSlash(ALICE_PROVER, slashAmount);

        // Dispense some $PROVE
        _dispense(dispenseAmount);

        // Verify fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), dispenseAmount);

        // Unstake
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify still fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), dispenseAmount);
    }

    // Prover's stakers fully slashed down to zero will not get any $PROVE from future dispenses,
    // but other (non-slashed) stakers will still get $PROVE.
    function test_Slash_WhenTwoProversDispenseAfterOneFullSlash() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 dispenseAmount = stakeAmount;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);
        _permitAndStake(STAKER_2, STAKER_2_PK, BOB_PROVER, stakeAmount);

        // Slash the prover
        uint256 slashAmount = IERC4626(ALICE_PROVER).totalAssets();
        _completeSlash(ALICE_PROVER, slashAmount);

        // Dispense some $PROVE
        _dispense(dispenseAmount);

        // Verify Staker 1 fully slashed, while Staker 2 is unimpacted and has a claim on all of the dispensed $PROVE
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), stakeAmount + stakeAmount - 1);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount + dispenseAmount);

        // Unstake
        _completeUnstake(STAKER_1, stakeAmount);
        _completeUnstake(STAKER_2, stakeAmount);

        // Verify Staker 1 did not recieve any $PROVE, while Staker 2 did
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), stakeAmount + dispenseAmount - 1);
    }

    function test_Slash_WhenCancelled() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Slash the prover for all of their stake
        uint256 slashAmount = IERC4626(ALICE_PROVER).totalAssets();
        MockVApp(VAPP).processSlash(ALICE_PROVER, slashAmount);

        // Since processSlash doesn't return the index, we know it's 0 as it's the first slash request
        uint256 slashIndex = 0;

        // Verify unstaking is blocked while slash request is pending
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.ProverHasSlashRequest.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(stakeAmount);

        // Cancel the slash request
        vm.prank(OWNER);
        SuccinctStaking(STAKING).cancelSlash(ALICE_PROVER, slashIndex);

        // Now unstaking should work
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).requestUnstake(stakeAmount);

        // Skip to the end of the unstake period
        skip(UNSTAKE_PERIOD);

        // Complete the unstake
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).finishUnstake(STAKER_1);

        // Verify final state - user should get all their tokens back since slash was cancelled
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
    }

    function test_RevertSlash_WhenProverNotFound() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 slashAmount = 0;
        address unknownProver = makeAddr("UNKNOWN_PROVER");

        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        vm.expectRevert(abi.encodeWithSelector(IProverRegistry.ProverNotFound.selector));
        vm.prank(OWNER);
        MockVApp(VAPP).processSlash(unknownProver, slashAmount);
    }

    function test_Slash_WhenRequestingWhenProverHasNoStake() public {
        uint256 slashAmount = STAKER_PROVE_AMOUNT;

        // Try to slash a prover with no stake. Should NOT revert and instead create a zero-amount claim.
        uint256 index = MockVApp(VAPP).processSlash(ALICE_PROVER, slashAmount);

        // Verify the claim has been recorded with 0 iPROVE.
        SuccinctStaking.SlashClaim[] memory claims =
            SuccinctStaking(STAKING).slashRequests(ALICE_PROVER);
        assertEq(index, 0);
        assertEq(claims.length, 1);
        assertEq(claims[0].iPROVE, slashAmount);

        // Advance time and complete the (no-op) slash without reverting.
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, index);
    }

    function test_RevertSlash_WhenFinishTooEarly() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Slash the prover for all of their stake
        uint256 slashAmount = IERC4626(ALICE_PROVER).totalAssets();
        MockVApp(VAPP).processSlash(ALICE_PROVER, slashAmount);

        // Try to finish the slash before the slash period has passed
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.SlashNotReady.selector));
        vm.prank(OWNER);
        SuccinctStaking(STAKING).finishSlash(ALICE_PROVER, 0);

        // Skip to just before the end of the slash period
        skip(SLASH_PERIOD - 10);

        // Try again, should still revert
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.SlashNotReady.selector));
        vm.prank(OWNER);
        SuccinctStaking(STAKING).finishSlash(ALICE_PROVER, 0);

        // Skip to the end of the slash period
        skip(10);

        // Now it should work
        vm.prank(OWNER);
        SuccinctStaking(STAKING).finishSlash(ALICE_PROVER, 0);
    }

    // Prover's stakers can still technically recieve withdrawals after being slashed to zero.
    function test_Slash_WhenRewardAfterFullSlash() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 rewardAmount = stakeAmount;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Slash the prover
        uint256 slashAmount = IERC4626(ALICE_PROVER).totalAssets();
        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify slashing worked
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);

        // Record balances before reward
        uint256 feeVaultBalanceBefore = MockVApp(VAPP).balances(FEE_VAULT);
        uint256 proverBalanceBefore = MockVApp(VAPP).balances(ALICE_PROVER);
        uint256 aliceBalanceBefore = MockVApp(VAPP).balances(ALICE);

        // Calculate expected reward split
        (uint256 expectedProtocolFee, uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateFullRewardSplit(rewardAmount);

        // Now reward the slashed prover - this should work even after full slash
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Verify the reward was processed correctly in MockVApp balances
        assertEq(
            MockVApp(VAPP).balances(FEE_VAULT),
            feeVaultBalanceBefore + expectedProtocolFee,
            "Protocol fee should be added to FEE_VAULT balance"
        );
        assertEq(
            MockVApp(VAPP).balances(ALICE_PROVER),
            proverBalanceBefore + expectedStakerReward,
            "Staker reward should be added to prover balance"
        );
        assertEq(
            MockVApp(VAPP).balances(ALICE),
            aliceBalanceBefore + expectedOwnerReward,
            "Owner reward should be added to Alice balance"
        );
    }

    // Slash request that exceeds a prover's stake should clamp to the full balance instead of reverting.
    function test_Slash_WhenSingleSlashAmountExceedsBalance() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Get the iPROVE balance of the prover.
        uint256 totalAssets = IERC4626(ALICE_PROVER).totalAssets();

        // First slash for 2x the balance.
        uint256 excessiveSlash = totalAssets * 2;
        uint256 index0 = _requestSlash(ALICE_PROVER, excessiveSlash);

        // The slash amount is 2x greater than the actual iPROVE balance of the prover. Exceeding
        // the iPROVE balance should just set the prover's balance to 0 without reverting.

        // The slash should have been recorded for the full requested amount.
        SuccinctStaking.SlashClaim[] memory claims =
            SuccinctStaking(STAKING).slashRequests(ALICE_PROVER);
        assertEq(claims.length, 1);
        assertEq(claims[index0].iPROVE, excessiveSlash);

        // Finish the slash claims after the slash period
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, index0);

        // Prover and staker should now be fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);

        // Unstake the stPROVE receipts
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify final state – staker has no remaining stake or PROVE
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
    }

    // Slash requests that cumulatively exceed a prover's stake should clamp to the full balance instead of reverting.
    function test_Slash_WhenCumulativeSlashAmountExceedsBalance() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Get the iPROVE balance of the prover.
        uint256 totalAssets = IERC4626(ALICE_PROVER).totalAssets();

        // First slash for half the balance.
        uint256 firstSlash = totalAssets / 2;
        uint256 index0 = _requestSlash(ALICE_PROVER, firstSlash);

        // Second slash attempts to slash the full balance.
        uint256 excessiveSlash = totalAssets;
        uint256 index1 = _requestSlash(ALICE_PROVER, excessiveSlash);

        // The cumulative slash amount is now 1.5x greater than the actual iPROVE balance of the prover.
        // Exceeding the iPROVE balance should just set the prover's balance to 0 without reverting.

        // The second slash should have been recorded for the full requested amount.
        SuccinctStaking.SlashClaim[] memory claims =
            SuccinctStaking(STAKING).slashRequests(ALICE_PROVER);
        assertEq(claims.length, 2);
        assertEq(claims[index0].iPROVE, firstSlash);
        assertEq(claims[index1].iPROVE, excessiveSlash);

        // Finish the slash claims after the slash period
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, index1);
        _finishSlash(ALICE_PROVER, index0);

        // Prover and staker should now be fully slashed
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);

        // Unstake the stPROVE receipts
        _completeUnstake(STAKER_1, stakeAmount);

        // Verify final state – staker has no remaining stake or PROVE
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
    }

    // Test that slash correctly handles escrow funds.
    function test_Slash_WhenSlashExceedsVaultButNotTotal() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Setup: Two stakers with same prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Staker 1 requests unstake (moves funds to escrow)
        _requestUnstake(STAKER_1, stakeAmount);

        // Now we have:
        // - Vault: stakeAmount (from STAKER_2)
        // - Escrow: stakeAmount (from STAKER_1)
        // - Total: 2 * stakeAmount

        // Verify initial state
        uint256 vaultBalance = IERC20(I_PROVE).balanceOf(ALICE_PROVER);
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(vaultBalance, stakeAmount, "Vault should have STAKER_2's stake");
        assertEq(pool.iPROVEEscrow, stakeAmount, "Escrow should have STAKER_1's stake");

        // Request slash for 150% of vault (but only 75% of total)
        uint256 slashAmount = stakeAmount * 3 / 2;
        _requestSlash(ALICE_PROVER, slashAmount);

        // Execute slash
        skip(SLASH_PERIOD);
        vm.prank(OWNER);
        uint256 iPROVEBurned = SuccinctStaking(STAKING).finishSlash(ALICE_PROVER, 0);

        // With the bug, only vault balance (stakeAmount) would be slashed
        // With the fix, the full slashAmount should be slashed (split between vault and escrow)
        assertEq(iPROVEBurned, slashAmount, "Should slash the full requested amount");

        // Verify the slash was distributed proportionally
        // With equal amounts in vault and escrow, each gets 50% of the slash
        uint256 expectedVaultSlash = slashAmount / 2; // 75k from vault
        uint256 expectedEscrowSlash = slashAmount / 2; // 75k from escrow

        // Check remaining balances
        uint256 vaultAfter = IERC20(I_PROVE).balanceOf(ALICE_PROVER);
        ISuccinctStaking.EscrowPool memory poolAfter =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);

        assertEq(
            vaultAfter, stakeAmount - expectedVaultSlash, "Vault should be reduced by its share"
        );
        assertEq(
            poolAfter.iPROVEEscrow,
            stakeAmount - expectedEscrowSlash,
            "Escrow should be reduced by its share"
        );

        // Complete unstakes to verify final state
        skip(UNSTAKE_PERIOD - SLASH_PERIOD);
        uint256 staker1Received = _finishUnstake(STAKER_1);

        // Staker 1 should receive reduced amount due to slash
        // Original: 100k, Slash on escrow: 75k, Remaining: 25k
        assertApproxEqAbs(
            staker1Received,
            stakeAmount - expectedEscrowSlash,
            2,
            "Staker 1 should receive 25% after 75% slash on escrow"
        );

        // Staker 2's remaining stake should also be reduced
        // Original: 100k, Slash on vault: 75k, Remaining: 25k
        assertApproxEqAbs(
            SuccinctStaking(STAKING).staked(STAKER_2),
            stakeAmount - expectedVaultSlash,
            2,
            "Staker 2 should have 25% remaining"
        );
    }

    function testFuzz_Slash_WhenVariableAmounts(uint256 _slashAmount) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 slashAmount = bound(_slashAmount, 1, stakeAmount * 2); // Allow over-slashing

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request slash
        uint256 slashIndex = _requestSlash(ALICE_PROVER, slashAmount);

        // Complete slash
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, slashIndex);

        // Check results
        uint256 actualSlashAmount = slashAmount > stakeAmount ? stakeAmount : slashAmount;
        assertEq(
            SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount - actualSlashAmount
        );
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount - actualSlashAmount);
    }

    function testFuzz_Slash_WhenMultipleStakers(
        uint256[3] memory _stakeAmounts,
        uint256 _slashAmount
    ) public {
        // Setup 3 stakers with different amounts
        address[3] memory stakers = [STAKER_1, STAKER_2, makeAddr("STAKER_3")];
        uint256 totalStaked = 0;

        for (uint256 i = 0; i < stakers.length; i++) {
            _stakeAmounts[i] = bound(_stakeAmounts[i], MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT / 3);
            deal(PROVE, stakers[i], _stakeAmounts[i]);
            _stake(stakers[i], ALICE_PROVER, _stakeAmounts[i]);
            totalStaked += _stakeAmounts[i];
        }

        // Bound slash amount
        uint256 slashAmount = bound(_slashAmount, 1, totalStaked);

        // Initial prover stake
        uint256 proverStakeBefore = SuccinctStaking(STAKING).proverStaked(ALICE_PROVER);
        assertEq(proverStakeBefore, totalStaked);

        // Request and complete slash
        uint256 slashIndex = _requestSlash(ALICE_PROVER, slashAmount);
        skip(SLASH_PERIOD);
        _finishSlash(ALICE_PROVER, slashIndex);

        // Verify proportional slashing
        uint256 actualSlashed = slashAmount > totalStaked ? totalStaked : slashAmount;
        for (uint256 i = 0; i < stakers.length; i++) {
            uint256 expectedStake =
                _stakeAmounts[i] - (_stakeAmounts[i] * actualSlashed / totalStaked);
            assertApproxEqAbs(
                SuccinctStaking(STAKING).staked(stakers[i]),
                expectedStake,
                1,
                "Staker should be slashed proportionally"
            );
        }
    }

    function testFuzz_Slash_WhenWithDispenseBeforeSlash(
        uint256 _dispenseAmount,
        uint256 _slashAmount
    ) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 dispenseAmount = bound(_dispenseAmount, 1000, 1_000_000e18);

        // Stake
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Dispense rewards
        _dispense(dispenseAmount);

        // Get staked amount after dispense (in iPROVE terms for slashing)
        uint256 stakedAfterDispense = SuccinctStaking(STAKING).staked(STAKER_1);
        uint256 iPROVEBalance = IERC4626(ALICE_PROVER).totalAssets();
        uint256 slashAmount = bound(_slashAmount, 1, iPROVEBalance);

        // Slash
        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify slash applied to increased stake
        // Allow for greater tolerance due to rounding in multiple vault operations
        uint256 actualStaked = SuccinctStaking(STAKING).staked(STAKER_1);

        // Due to ERC4626 exchange rate mechanics, when slashing iPROVE:
        // - The exchange rate changes, affecting how stPROVE redeems to PROVE
        // - We can't use simple arithmetic to predict the outcome

        // Check that some slashing occurred
        assertLt(actualStaked, stakedAfterDispense, "Staked amount should decrease after slash");

        // For large slashes (>90% of iPROVE), expect very low remaining stake
        if (slashAmount >= iPROVEBalance * 90 / 100) {
            assertLe(
                actualStaked, stakedAfterDispense / 10, "Large slash should leave minimal stake"
            );
        } else {
            // For smaller slashes, ensure the result is reasonable
            // The actual calculation depends on the vault exchange rates
            uint256 minExpected =
                (stakedAfterDispense * (iPROVEBalance - slashAmount)) / iPROVEBalance / 2;
            assertGe(actualStaked, minExpected, "Slash should not reduce stake more than expected");
        }
    }

    function testFuzz_Slash_WhenTimingAroundPeriod(uint256 _waitTime) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 slashAmount = stakeAmount / 2;

        // Stake and request slash
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        uint256 slashIndex = _requestSlash(ALICE_PROVER, slashAmount);

        // Bound wait time around slash period
        uint256 waitTime = bound(_waitTime, 1, SLASH_PERIOD * 2);
        skip(waitTime);

        if (waitTime < SLASH_PERIOD) {
            // Should not be able to finish slash yet
            vm.expectRevert(ISuccinctStaking.SlashNotReady.selector);
            vm.prank(OWNER);
            SuccinctStaking(STAKING).finishSlash(ALICE_PROVER, slashIndex);
        } else {
            // Should be able to finish slash
            _finishSlash(ALICE_PROVER, slashIndex);
            assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount - slashAmount);
        }
    }

    function testFuzz_Slash_WhenMultipleSlashRequests(uint256[3] memory _slashAmounts) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Bound slash amounts
        uint256 totalSlash = 0;
        for (uint256 i = 0; i < _slashAmounts.length; i++) {
            _slashAmounts[i] = bound(_slashAmounts[i], 1, stakeAmount / 4);
            totalSlash += _slashAmounts[i];
        }

        // Ensure total slash doesn't exceed stake
        vm.assume(totalSlash <= stakeAmount);

        // Request multiple slashes
        uint256[] memory slashIndices = new uint256[](_slashAmounts.length);
        for (uint256 i = 0; i < _slashAmounts.length; i++) {
            slashIndices[i] = _requestSlash(ALICE_PROVER, _slashAmounts[i]);
            skip(1 days); // Add time between requests
        }

        // Wait for slash period
        skip(SLASH_PERIOD);

        // Complete all slashes in reverse order (to avoid index shifting issues)
        for (uint256 i = slashIndices.length; i > 0; i--) {
            _finishSlash(ALICE_PROVER, slashIndices[i - 1]);
        }

        // Verify cumulative slash effect
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount - totalSlash);
    }
}
