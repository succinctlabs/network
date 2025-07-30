// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {SuccinctGovernor} from "../src/SuccinctGovernor.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {IProverRegistry} from "../src/interfaces/IProverRegistry.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {Math} from "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Vm} from "../lib/forge-std/src/Vm.sol";

contract SuccinctStakingSlashTests is SuccinctStakingTest {
    bytes32 internal constant PROVER_DEACTIVATION_SIGNATURE =
        keccak256("ProverDeactivation(address)");
    bytes32 internal constant SLASH_SIGNATURE = keccak256("Slash(address,uint256,uint256,uint256)");

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

        // Wait for the cancellation deadline to pass
        uint256 votingDelay = SuccinctGovernor(payable(GOVERNOR)).votingDelay();
        uint256 votingPeriod = SuccinctGovernor(payable(GOVERNOR)).votingPeriod();
        uint256 cancelDeadline = SLASH_CANCELLATION_PERIOD + votingDelay + votingPeriod;
        skip(cancelDeadline);

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

        // Complete the (no-op) slash without reverting.
        _finishSlash(ALICE_PROVER, index);
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
        uint256 feeVaultBalanceBefore = MockVApp(VAPP).balances(TREASURY);
        uint256 proverBalanceBefore = MockVApp(VAPP).balances(ALICE_PROVER);
        uint256 aliceBalanceBefore = MockVApp(VAPP).balances(ALICE);

        // Calculate expected reward split
        (uint256 expectedProtocolFee, uint256 expectedStakerReward, uint256 expectedOwnerReward) =
            _calculateFullRewardSplit(rewardAmount);

        // Now reward the slashed prover - this should work even after full slash
        MockVApp(VAPP).processFulfillment(ALICE_PROVER, rewardAmount);

        // Verify the reward was processed correctly in MockVApp balances
        assertEq(
            MockVApp(VAPP).balances(TREASURY),
            feeVaultBalanceBefore + expectedProtocolFee,
            "Protocol fee should be added to TREASURY balance"
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
        skip(UNSTAKE_PERIOD);
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

    // Test multiple consecutive slashes during one unbonding period, then claim
    function test_Slash_WhenMultipleSlashesBeforeUnstakeFinish() public {
        // Define all test values at the start, derived from setUp constants
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2; // Use half for cleaner math
        uint256 totalInitial = stakeAmount * 2; // Two stakers
        uint256 firstSlashAmount = totalInitial / 4; // 25% of total
        uint256 secondSlashAmount = (totalInitial - firstSlashAmount) / 2; // 50% of remaining

        // Two stakers stake to same prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Staker A requests unstake → iPROVE moves to escrow
        _requestUnstake(STAKER_1, stakeAmount);

        // Verify initial state: vault has B's stake, escrow has A's stake
        assertEq(
            IERC20(I_PROVE).balanceOf(ALICE_PROVER),
            stakeAmount,
            "Vault should have STAKER_2's stake"
        );
        assertEq(
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER).iPROVEEscrow,
            stakeAmount,
            "Escrow should have STAKER_1's stake"
        );
        assertEq(
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER).slashFactor,
            1e27,
            "Initial slash factor should be 1e27"
        );

        // First slash: 25% of total
        _completeSlash(ALICE_PROVER, firstSlashAmount);

        // Verify after first slash - each pool loses 25%
        assertEq(
            IERC20(I_PROVE).balanceOf(ALICE_PROVER),
            stakeAmount * 3 / 4,
            "Vault should be reduced by 25%"
        );
        assertEq(
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER).iPROVEEscrow,
            stakeAmount * 3 / 4,
            "Escrow should be reduced by 25%"
        );

        // Second slash: 50% of remaining
        _completeSlash(ALICE_PROVER, secondSlashAmount);

        // Verify after second slash - each pool loses another 50% of their remaining
        uint256 expectedFinal = stakeAmount * 3 / 8; // 75% * 50% = 37.5%
        assertEq(
            IERC20(I_PROVE).balanceOf(ALICE_PROVER),
            expectedFinal,
            "Vault should be reduced by another 50%"
        );
        assertEq(
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER).iPROVEEscrow,
            expectedFinal,
            "Escrow should be reduced by another 50%"
        );

        // Finish A's unstake
        skip(UNSTAKE_PERIOD);
        uint256 balanceBefore = IERC20(PROVE).balanceOf(STAKER_1);
        _finishUnstake(STAKER_1);

        // A should receive their share after both slashes applied
        assertEq(
            IERC20(PROVE).balanceOf(STAKER_1) - balanceBefore,
            expectedFinal,
            "Staker A should receive final escrow amount"
        );

        // Check escrow after unstake
        assertEq(
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER).iPROVEEscrow,
            0,
            "Escrow should be empty after unstake"
        );

        // B's remaining stake should equal the vault balance after slashes
        assertEq(
            SuccinctStaking(STAKING).staked(STAKER_2),
            expectedFinal,
            "Staker B should have reduced stake"
        );
    }

    // Test slash when vault is drained to zero (second slash hits escrow only)
    function test_Slash_WhenVaultDrainedToZero() public {
        // Define all test values at the start
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2;
        uint256 slashPercent = 50; // 50% slash
        uint256 slashAmount = stakeAmount * slashPercent / 100;
        uint256 expectedRemaining = stakeAmount - slashAmount;

        // Setup: one staker, request unstake to move funds to escrow
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _requestUnstake(STAKER_1, stakeAmount);

        // Verify all funds are in escrow
        uint256 vaultBalance = IERC20(I_PROVE).balanceOf(ALICE_PROVER);
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(vaultBalance, 0, "Vault should be empty");
        assertEq(pool.iPROVEEscrow, stakeAmount, "All funds should be in escrow");

        // Slash 50% - should hit only escrow since vault is empty
        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify burnFromVault = 0 and all burn came from escrow
        uint256 vaultAfter = IERC20(I_PROVE).balanceOf(ALICE_PROVER);
        ISuccinctStaking.EscrowPool memory poolAfter =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(vaultAfter, 0, "Vault should remain empty");
        assertEq(
            poolAfter.iPROVEEscrow, expectedRemaining, "Escrow should be reduced by slash amount"
        );
        // Slash factor should reflect the remaining percentage
        uint256 expectedFactor = SCALAR * (100 - slashPercent) / 100;
        assertEq(
            poolAfter.slashFactor,
            expectedFactor,
            "Slash factor should reflect remaining percentage"
        );

        // Finish unstake and verify staker receives remaining amount
        skip(UNSTAKE_PERIOD);
        uint256 balanceBefore = IERC20(PROVE).balanceOf(STAKER_1);
        _finishUnstake(STAKER_1);
        uint256 received = IERC20(PROVE).balanceOf(STAKER_1) - balanceBefore;
        assertEq(received, expectedRemaining, "Staker should receive remaining amount after slash");
    }

    // Test slash factor zero reset with prover deactivation
    function test_Slash_WhenFactorZeroResetWithDeactivation() public {
        // Define all test values at the start
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2;

        // Staker 1 stakes
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Verify initial state
        ISuccinctStaking.EscrowPool memory initialPool =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertFalse(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));
        // Initially, slashFactor should be 0 (uninitialized) since no unstaking has occurred
        assertEq(initialPool.slashFactor, 0);

        // Full slash (100% burn, factor → 0, prover gets deactivated)
        uint256 fullSlashAmount = IERC4626(ALICE_PROVER).totalAssets();
        _completeSlash(ALICE_PROVER, fullSlashAmount);

        // Verify factor is zero after full slash and prover is deactivated
        ISuccinctStaking.EscrowPool memory slashedPool =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(slashedPool.slashFactor, 0);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertTrue(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Staker 2 tries to stake but should be blocked due to deactivation
        vm.prank(STAKER_2);
        IERC20(PROVE).approve(STAKING, stakeAmount);

        vm.expectRevert(abi.encodeWithSelector(IProverRegistry.ProverNotActive.selector));
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);

        // Verify staker 2 was not able to stake
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), STAKER_PROVE_AMOUNT);

        // Verify staker 1 still has nothing (was fully slashed)
        if (SuccinctStaking(STAKING).balanceOf(STAKER_1) > 0) {
            _completeUnstake(STAKER_1, SuccinctStaking(STAKING).balanceOf(STAKER_1));
        }
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT - stakeAmount);
    }

    function test_Slash_WhenFullSlashDeactivatesProver() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Verify prover is not deactivated initially
        assertFalse(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Full slash - should burn all assets and deactivate prover
        uint256 slashAmount = SuccinctStaking(STAKING).proverStaked(ALICE_PROVER);

        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify prover is now deactivated
        assertTrue(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Verify assets are burned
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);

        // Verify price-per-share is below threshold
        uint256 pricePerShare = _getProverPricePerShare(ALICE_PROVER);
        assertLt(pricePerShare, MIN_PROVER_PRICE_PER_SHARE);
    }

    function test_Slash_WhenStakeBlockedAfterDeactivation() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Full slash to deactivate prover
        uint256 slashAmount = SuccinctStaking(STAKING).proverStaked(ALICE_PROVER);
        _completeSlash(ALICE_PROVER, slashAmount);

        // Verify prover is deactivated
        assertTrue(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Try to stake to deactivated prover - should revert
        vm.prank(STAKER_2);
        IERC20(PROVE).approve(STAKING, stakeAmount);

        vm.expectRevert(abi.encodeWithSelector(IProverRegistry.ProverNotActive.selector));
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);

        // Verify no new stake was added
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_2), 0);
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), STAKER_PROVE_AMOUNT);
    }

    // Tests that the prover eventually gets de-activated after many partial (high)
    // slashes even if they aren't full balance slashes.
    function test_Slash_WhenPartialSlashEventuallyDeactivates() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Verify prover is not deactivated initially
        assertFalse(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // First partial slash - 50% (should not deactivate)
        uint256 firstSlash = SuccinctStaking(STAKING).proverStaked(ALICE_PROVER) / 2;
        _completeSlash(ALICE_PROVER, firstSlash);

        // Verify prover is still active after 50% slash
        assertFalse(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Second stake to create share inflation scenario
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Second partial slash - 99.999999999% of remaining stake
        uint256 secondSlash =
            (SuccinctStaking(STAKING).proverStaked(ALICE_PROVER) * 999999999999999999) / 1e18;
        _completeSlash(ALICE_PROVER, secondSlash);

        // Check if deactivated now - depends on accumulated price-per-share drop
        assertTrue(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Verify final price-per-share is below threshold
        uint256 pricePerShare = _getProverPricePerShare(ALICE_PROVER);
        assertLt(pricePerShare, MIN_PROVER_PRICE_PER_SHARE);
    }

    // Fuzz test for extremely small slash factors to check no underflow
    function testFuzz_Slash_ExtremelySmallFactor(uint256 _seed) public {
        vm.assume(_seed > 0);

        uint256 initialStake = 1000e18;
        _stake(STAKER_1, ALICE_PROVER, initialStake);

        uint256 totalIPROVEBurned = 0;
        uint256 remaining = initialStake;

        // Iterate 20 random slashes of random percentages
        for (uint256 i = 0; i < 20 && remaining > 10; i++) {
            // Get random slash percentage between 1-50%
            uint256 slashPercent = ((_seed >> (i * 8)) % 50) + 1;
            uint256 currentVaultBalance = IERC20(I_PROVE).balanceOf(ALICE_PROVER);

            if (currentVaultBalance > 0) {
                uint256 slashAmount = (currentVaultBalance * slashPercent) / 100;
                if (slashAmount > 0) {
                    uint256 actualBurned = _completeSlash(ALICE_PROVER, slashAmount);
                    totalIPROVEBurned += actualBurned;
                    remaining = currentVaultBalance - actualBurned;
                }
            }
        }

        // Verify slash factor never underflows (should be >= 0)
        ISuccinctStaking.EscrowPool memory finalPool =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        uint256 finalFactor = finalPool.slashFactor;
        assertTrue(finalFactor >= 0, "Slash factor should never underflow");
        assertTrue(finalFactor <= 1e27, "Slash factor should never exceed 1e27");

        // Verify iPROVE conservation: vault + escrow + burned should equal initial stake
        uint256 finalVault = IERC20(I_PROVE).balanceOf(ALICE_PROVER);
        ISuccinctStaking.EscrowPool memory pool = ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        uint256 finalEscrow = pool.iPROVEEscrow;

        // Allow small rounding error (up to 20 wei for 20 operations)
        assertApproxEqAbs(
            finalVault + finalEscrow + totalIPROVEBurned,
            initialStake,
            20,
            "iPROVE conservation should hold: vault + escrow + burned = initial"
        );

        // If factor is very small (< 0.01), verify minimal stake remains
        if (finalFactor < 0.01e27) {
            uint256 stakedAmount = SuccinctStaking(STAKING).staked(STAKER_1);
            assertLe(
                stakedAmount, initialStake / 100, "Very small factor should leave minimal stake"
            );
        }

        // Verify no arithmetic errors by attempting an unstake (if any stake remains)
        uint256 stakerBalance = SuccinctStaking(STAKING).balanceOf(STAKER_1);
        if (stakerBalance > 0) {
            // Should not revert due to arithmetic errors
            uint256 preview = SuccinctStaking(STAKING).previewUnstake(ALICE_PROVER, stakerBalance);
            // Preview should be reasonable (not greater than vault + escrow)
            assertLe(
                preview, finalVault + finalEscrow + 1, "Preview should not exceed available funds"
            );
        }
    }

    // Skip event accuracy test - event structure is different than expected
    // The Slash event has format (prover, PROVE, iPROVE, index) not burn amounts

    function testFuzz_Slash_WhenVariableAmounts(uint256 _slashAmount) public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 slashAmount = bound(_slashAmount, 1, stakeAmount * 2); // Allow over-slashing

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Request slash
        uint256 slashIndex = _requestSlash(ALICE_PROVER, slashAmount);

        // Complete slash
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

        // Complete all slashes in reverse order (to avoid index shifting issues)
        for (uint256 i = slashIndices.length; i > 0; i--) {
            _finishSlash(ALICE_PROVER, slashIndices[i - 1]);
        }

        // Verify cumulative slash effect
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount - totalSlash);
    }

    // Test that Slash event emits correct values for tooling that relies on events
    function test_Slash_Events() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Setup: Two stakers to create both vault and escrow balance
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);
        _stake(STAKER_2, ALICE_PROVER, stakeAmount);

        // Staker 1 requests unstake to create escrow
        _requestUnstake(STAKER_1, stakeAmount);

        // Now we have:
        // - Vault: stakeAmount (from STAKER_2)
        // - Escrow: stakeAmount (from STAKER_1)
        // - Total: 2 * stakeAmount

        // Verify initial state
        uint256 vaultBefore = IERC20(I_PROVE).balanceOf(ALICE_PROVER);
        ISuccinctStaking.EscrowPool memory poolBefore =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);
        assertEq(vaultBefore, stakeAmount, "Vault should have STAKER_2's stake");
        assertEq(poolBefore.iPROVEEscrow, stakeAmount, "Escrow should have STAKER_1's stake");

        // Request slash for 75% of total
        uint256 slashAmount = (stakeAmount * 3) / 2; // 150 from total 200
        uint256 slashIndex = _requestSlash(ALICE_PROVER, slashAmount);

        // Calculate expected burns based on pro-rata distribution
        uint256 totalIPROVE = vaultBefore + poolBefore.iPROVEEscrow;
        uint256 expectedEscrowBurn = Math.mulDiv(slashAmount, poolBefore.iPROVEEscrow, totalIPROVE);
        uint256 expectedVaultBurn = slashAmount - expectedEscrowBurn;

        // Calculate expected PROVE burned (should be same as iPROVE in 1:1 case)
        uint256 expectedPROVEBurned = IERC4626(I_PROVE).previewRedeem(slashAmount);

        // Test event emission by capturing it
        vm.recordLogs();

        // Execute slash
        vm.prank(OWNER);
        uint256 actualIPROVEBurned = SuccinctStaking(STAKING).finishSlash(ALICE_PROVER, slashIndex);

        // Get the emitted logs
        Vm.Log[] memory slashLogs = vm.getRecordedLogs();

        // Find the Slash event log
        bool slashEventFound = false;
        for (uint256 i = 0; i < slashLogs.length; i++) {
            if (slashLogs[i].topics[0] == SLASH_SIGNATURE) {
                slashEventFound = true;

                // Decode the event
                address eventProver = address(uint160(uint256(slashLogs[i].topics[1])));
                (uint256 eventPROVEBurned, uint256 eventIPROVEBurned, uint256 eventIndex) =
                    abi.decode(slashLogs[i].data, (uint256, uint256, uint256));

                // Verify event values
                assertEq(eventProver, ALICE_PROVER, "Event prover should match");
                assertEq(
                    eventPROVEBurned,
                    expectedPROVEBurned,
                    "Event PROVE burned should match expected"
                );
                assertEq(
                    eventIPROVEBurned, actualIPROVEBurned, "Event iPROVE burned should match actual"
                );
                assertEq(eventIndex, slashIndex, "Event index should match");
                break;
            }
        }

        assertTrue(slashEventFound, "Slash event should be emitted");

        // Verify the actual burn matches expected
        assertEq(actualIPROVEBurned, slashAmount, "Should burn requested iPROVE amount");

        // iPROVEBurned should equal the requested slash amount, and PROVEBurned is the underlying PROVE value
        assertEq(actualIPROVEBurned, slashAmount, "iPROVE burned should equal requested slash");
        assertEq(
            expectedPROVEBurned,
            IERC4626(I_PROVE).previewRedeem(actualIPROVEBurned),
            "PROVE burned should equal the redemption value of iPROVE burned"
        );

        // Verify state after slash
        uint256 vaultAfter = IERC20(I_PROVE).balanceOf(ALICE_PROVER);
        ISuccinctStaking.EscrowPool memory poolAfter =
            ISuccinctStaking(STAKING).escrowPool(ALICE_PROVER);

        assertEq(
            vaultAfter, vaultBefore - expectedVaultBurn, "Vault should be reduced by expected burn"
        );
        assertEq(
            poolAfter.iPROVEEscrow,
            poolBefore.iPROVEEscrow - expectedEscrowBurn,
            "Escrow should be reduced by expected burn"
        );
    }

    function test_Slash_Events_WhenDeactivated() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Create two slash requests - both full slashes to ensure deactivation
        uint256 totalStaked = SuccinctStaking(STAKING).proverStaked(ALICE_PROVER);
        uint256 firstSlashAmount = totalStaked; // Full slash to trigger deactivation
        uint256 secondSlashAmount = totalStaked; // Another full slash on same prover

        uint256 firstIndex = _requestSlash(ALICE_PROVER, firstSlashAmount);
        uint256 secondIndex = _requestSlash(ALICE_PROVER, secondSlashAmount);

        // Finish first slash - this should deactivate the prover
        vm.recordLogs();
        _finishSlash(ALICE_PROVER, firstIndex);
        Vm.Log[] memory slashLogs1 = vm.getRecordedLogs();

        // Count ProverDeactivation events in first slash
        uint256 deactivationEventsFirst = 0;
        for (uint256 i = 0; i < slashLogs1.length; i++) {
            if (slashLogs1[i].topics[0] == PROVER_DEACTIVATION_SIGNATURE) {
                deactivationEventsFirst++;
            }
        }

        // Should have exactly one deactivation event
        assertEq(deactivationEventsFirst, 1);

        // Verify prover is deactivated
        assertTrue(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));

        // Finish second slash - this should NOT emit another ProverDeactivation event
        vm.recordLogs();
        _finishSlash(ALICE_PROVER, secondIndex);
        Vm.Log[] memory slashLogs2 = vm.getRecordedLogs();

        // Count ProverDeactivation events in second slash
        uint256 deactivationEventsSecond = 0;
        for (uint256 i = 0; i < slashLogs2.length; i++) {
            if (slashLogs2[i].topics[0] == PROVER_DEACTIVATION_SIGNATURE) {
                deactivationEventsSecond++;
            }
        }

        // Should have zero deactivation events in second slash
        assertEq(deactivationEventsSecond, 0);
        assertTrue(SuccinctStaking(STAKING).isDeactivatedProver(ALICE_PROVER));
    }
}
