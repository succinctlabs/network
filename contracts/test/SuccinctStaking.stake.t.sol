// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {IProverRegistry} from "../src/interfaces/IProverRegistry.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ERC20Permit} from
    "../lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract SuccinctStakingStakeTests is SuccinctStakingTest {
    function test_Stake_WhenValid() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Initial state checks
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), 0);

        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, stakeAmount);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctStaking.ProverBound(STAKER_1, ALICE_PROVER);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctStaking.Stake(STAKER_1, ALICE_PROVER, stakeAmount, stakeAmount, stakeAmount);

        // Stake to Alice prover.
        vm.prank(STAKER_1);
        uint256 stPROVE = SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);
        assertEq(stPROVE, stakeAmount);

        // Check balances
        assertEq(SuccinctStaking(STAKING).stakedTo(STAKER_1), ALICE_PROVER);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewUnstake(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKING), DISPENSE_AMOUNT);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount);
    }

    function test_RevertStake_WhenProverNotFound() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        address unknownProver = makeAddr("UNKNOWN_PROVER");

        // Stake to unknown prover.
        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, stakeAmount);
        vm.expectRevert(abi.encodeWithSelector(IProverRegistry.ProverNotFound.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(unknownProver, stakeAmount);
    }

    // Must stake a positive amount
    function test_RevertStake_WhenZeroAmount() public {
        uint256 stakeAmount = 0;

        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, stakeAmount);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.ZeroAmount.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);
    }

    // Must stake over min stake amount
    function test_RevertStake_WhenBelowMinStakeAmount() public {
        uint256 stakeAmount = MIN_STAKE_AMOUNT - 1;

        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, stakeAmount);

        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.StakeBelowMinimum.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);
    }

    // Not allowed to stake to a deactivated prover
    function test_RevertStake_WhenProverDeactivated() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Staker 1 stakes to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Full slash to deactivate prover
        uint256 slashAmount = SuccinctStaking(STAKING).proverStaked(ALICE_PROVER);
        _completeSlash(ALICE_PROVER, slashAmount);

        // Staker 1 stakes to deactivated prover
        vm.prank(STAKER_2);
        IERC20(PROVE).approve(STAKING, stakeAmount);
        vm.expectRevert(abi.encodeWithSelector(IProverRegistry.ProverNotActive.selector));
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);
    }

    // Not allowed to stake to multiple provers at once
    function test_RevertStake_WhenStakedToADifferentProver() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2;

        // Staker 1 deposits to Alice prover
        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Stake 1 deposits to Bob prover while staked to Alice prover
        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, stakeAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISuccinctStaking.AlreadyStakedWithDifferentProver.selector, ALICE_PROVER
            )
        );
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(BOB_PROVER, stakeAmount);
    }

    // Not allowed to stake to a prover that has a pending slash request
    function test_RevertStake_WhenProverHasSlashRequest() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Create a slash request for Alice prover.
        _requestSlash(ALICE_PROVER, 1);

        // Stake 1 stakes to Alice prover.
        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, stakeAmount);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.ProverHasSlashRequest.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);
    }

    // Staking would give 0 $iPROVE, which should revert.
    function test_RevertStake_WheniPROVEReceiptAmountIsZero() public {
        uint256 stakeAmount = MIN_STAKE_AMOUNT;

        // Stake 1 stakes to Alice prover.
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Give an extremely large dispense amount.
        uint256 rewardAmount = 1_000_000_000_000_000_000_000_000_000e18;
        deal(PROVE, I_PROVE, rewardAmount);

        // Stake 2 stakes to Alice prover.
        vm.prank(STAKER_2);
        IERC20(PROVE).approve(STAKING, stakeAmount);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.ZeroReceiptAmount.selector));
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);
    }

    // Staking would give 0 $PROVER-N, which should revert.
    function test_RevertStake_WhenProverNReceiptAmountIsZero() public {
        uint256 stakeAmount = MIN_STAKE_AMOUNT;

        // Stake 1 stakes to Alice prover.
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Give an extremely large reward amount to the prover.
        uint256 rewardAmount = 1_000_000_000_000_000_000_000_000_000e18;
        deal(I_PROVE, ALICE_PROVER, rewardAmount);

        // Stake 2 stakes to Alice prover.
        vm.prank(STAKER_2);
        IERC20(PROVE).approve(STAKING, stakeAmount);
        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.ZeroReceiptAmount.selector));
        vm.prank(STAKER_2);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);
    }

    function test_PermitAndStake_WhenValid() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        uint256 stPROVE =
            _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount, deadline);
        assertEq(stPROVE, stakeAmount);

        // Check balances
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), 0);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount);
    }

    function test_PermitAndStake_WhenLessThanApproved() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT / 2;
        uint256 deadline = block.timestamp + 1 days;

        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount, deadline);

        // Check balances - should have stakeAmount in ALICE_PROVER and remaining in STAKER_1
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT - stakeAmount);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount);
    }

    // An attacker frontrun by spending a staker's permit signature, but because the allowance
    // equalling the amount being staked skips the PROVE.permit() call, this does not block the
    // SuccinctStaking.permitAndStake() call.
    function test_PermitAndStake_WhenAttackerFrontruns() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        // Staker signs a permit for the amount than they intend to stake.
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(STAKER_1_PK, STAKER_1, ALICE_PROVER, stakeAmount, deadline);

        // An attacker spends the permit (simulating a frontrun).
        vm.prank(OWNER);
        ERC20Permit(PROVE).permit(STAKER_1, ALICE_PROVER, stakeAmount, deadline, v, r, s);

        // The stake still succeeds because permit is now skipped.
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).permitAndStake(
            ALICE_PROVER, STAKER_1, stakeAmount, deadline, v, r, s
        );
    }

    function test_RevertPermitAndStake_WhenSignatureInvalid() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 deadline = block.timestamp + 1 days;
        uint256 wrongPK = 0xBEEF;

        // Get permit signature with wrong private key
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(wrongPK, STAKER_1, ALICE_PROVER, stakeAmount, deadline);

        // Should revert with invalid signature
        vm.prank(STAKER_1);
        vm.expectRevert();
        SuccinctStaking(STAKING).permitAndStake(
            ALICE_PROVER, STAKER_1, stakeAmount, deadline, v, r, s
        );

        // Check balances
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
    }

    function test_RevertPermitAndStake_WhenDeadlineExpired() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 deadline = block.timestamp - 1;

        // Get permit signature
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(STAKER_1_PK, STAKER_1, ALICE_PROVER, stakeAmount, deadline);

        // Should revert with expired deadline
        vm.prank(STAKER_1);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline)
        );
        SuccinctStaking(STAKING).permitAndStake(
            ALICE_PROVER, STAKER_1, stakeAmount, deadline, v, r, s
        );

        // Check balances unchanged
        assertEq(IERC20(PROVE).balanceOf(STAKING), DISPENSE_AMOUNT);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT);
    }

    function test_RevertPermitAndStake_WhenNotEnoughApproved() public {
        uint256 approveAmount = STAKER_PROVE_AMOUNT / 2;
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        // Get permit signature for less than deposit amount
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(STAKER_1_PK, STAKER_1, ALICE_PROVER, approveAmount, deadline);

        // Should revert with the same InvalidSigner error as in the invalid signature test
        vm.prank(STAKER_1);
        vm.expectRevert();
        SuccinctStaking(STAKING).permitAndStake(
            ALICE_PROVER, STAKER_1, stakeAmount, deadline, v, r, s
        );

        // Check balances unchanged
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
    }

    function testFuzz_Stake_WhenValid(uint256 _stakeAmount) public {
        uint256 stakeAmount = bound(_stakeAmount, MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT);

        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Check balances
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT - stakeAmount);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount);
    }

    function testFuzz_PermitAndStake_WhenValid(uint256 _stakeAmount) public {
        uint256 stakeAmount = bound(_stakeAmount, MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT);

        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount);

        // Check balances
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT - stakeAmount);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount);
    }

    function testFuzz_Stake_WhenMultipleStakersSameProver(
        uint256 _stakeAmount1,
        uint256 _stakeAmount2
    ) public {
        uint256 stakeAmount1 = bound(_stakeAmount1, MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT);
        uint256 stakeAmount2 = bound(_stakeAmount2, MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT);

        _stake(STAKER_1, ALICE_PROVER, stakeAmount1);
        _stake(STAKER_2, ALICE_PROVER, stakeAmount2);

        // Check balances
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount1);
        assertEq(IERC20(STAKING).balanceOf(STAKER_2), stakeAmount2);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount1);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), stakeAmount2);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT - stakeAmount1);
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), STAKER_PROVE_AMOUNT - stakeAmount2);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount1 + stakeAmount2);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount1 + stakeAmount2);
    }

    function testFuzz_PermitAndStake_WhenMultipleStakersDifferentProvers(
        uint256 _stakeAmount1,
        uint256 _stakeAmount2
    ) public {
        uint256 stakeAmount1 = bound(_stakeAmount1, MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT);
        uint256 stakeAmount2 = bound(_stakeAmount2, MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT);

        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount1);
        _permitAndStake(STAKER_2, STAKER_2_PK, BOB_PROVER, stakeAmount2);

        // Check balances
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount1);
        assertEq(IERC20(STAKING).balanceOf(STAKER_2), stakeAmount2);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount1);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_2), stakeAmount2);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT - stakeAmount1);
        assertEq(IERC20(PROVE).balanceOf(STAKER_2), STAKER_PROVE_AMOUNT - stakeAmount2);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount1);
        assertEq(IERC20(I_PROVE).balanceOf(BOB_PROVER), stakeAmount2);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount1 + stakeAmount2);
    }
}
