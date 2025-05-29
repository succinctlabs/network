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
        SuccinctStaking(STAKING).finishUnstake();

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

    function test_RevertSlash_WhenRequestingWhenProverHasNoStake() public {
        uint256 slashAmount = STAKER_PROVE_AMOUNT;

        // Try to slash a prover with no stake
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.InsufficientStakeBalance.selector));
        MockVApp(VAPP).processSlash(ALICE_PROVER, slashAmount);
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
}
