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

        // Stake to Alice prover.
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Check balances
        assertEq(SuccinctStaking(STAKING).stakedTo(STAKER_1), ALICE_PROVER);
        assertEq(SuccinctStaking(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).staked(STAKER_1), stakeAmount);
        assertEq(SuccinctStaking(STAKING).unstakePending(STAKER_1), 0);
        assertEq(SuccinctStaking(STAKING).previewRedeem(ALICE_PROVER, stakeAmount), stakeAmount);
        assertEq(SuccinctStaking(STAKING).proverStaked(ALICE_PROVER), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(STAKING), STAKING_PROVE_AMOUNT);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), stakeAmount);
        assertEq(IERC20(STAKING).balanceOf(STAKER_1), stakeAmount);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), stakeAmount);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), stakeAmount);
    }

    function test_RevertStake_WhenProverNotFound() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        address unknownProver = makeAddr("UNKNOWN_PROVER");

        // Initial state checks
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), stakeAmount);
        assertEq(IERC20(I_PROVE).balanceOf(ALICE_PROVER), 0);
        assertEq(IERC20(ALICE_PROVER).balanceOf(STAKING), 0);
        assertEq(IERC20(PROVE).balanceOf(I_PROVE), 0);

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

        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.ZeroAmount.selector));
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, stakeAmount);
    }

    // Must stake over min stake amount
    function test_RevertStake_WhenBelowMinStakeAmount() public {
        uint256 stakeAmount = MIN_STAKE_AMOUNT - 1;

        vm.expectRevert(abi.encodeWithSelector(ISuccinctStaking.StakeBelowMinimum.selector));
        vm.prank(STAKER_1);
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

    function test_PermitAndStake_WhenValid() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        _permitAndStake(STAKER_1, STAKER_1_PK, ALICE_PROVER, stakeAmount, deadline);

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

    function test_RevertPermitAndStake_WhenSignatureInvalid() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 deadline = block.timestamp + 1 days;
        uint256 wrongPK = 0xBEEF;

        // Get permit signature with wrong private key
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(wrongPK, STAKER_1, stakeAmount, deadline);

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
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(STAKER_1_PK, STAKER_1, stakeAmount, deadline);

        // Should revert with expired deadline
        vm.prank(STAKER_1);
        vm.expectRevert(
            abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, deadline)
        );
        SuccinctStaking(STAKING).permitAndStake(
            ALICE_PROVER, STAKER_1, stakeAmount, deadline, v, r, s
        );

        // Check balances unchanged
        assertEq(IERC20(PROVE).balanceOf(STAKING), STAKING_PROVE_AMOUNT);
        assertEq(IERC20(PROVE).balanceOf(STAKER_1), STAKER_PROVE_AMOUNT);
    }

    function test_RevertPermitAndStake_WhenNotEnoughApproved() public {
        uint256 approveAmount = STAKER_PROVE_AMOUNT / 2;
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;
        uint256 deadline = block.timestamp + 1 days;

        // Get permit signature for less than deposit amount
        (uint8 v, bytes32 r, bytes32 s) =
            _signPermit(STAKER_1_PK, STAKER_1, approveAmount, deadline);

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
}
