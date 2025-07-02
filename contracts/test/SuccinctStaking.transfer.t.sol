// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IIntermediateSuccinct} from "../src/interfaces/IIntermediateSuccinct.sol";
import {IERC4626} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

// Ensures that $iPROVE, $PROVER-N, and $stPROVE cannot be transferred (or deposited/withdrawn directly).

contract SuccinctStakingTransferTests is SuccinctStakingTest {
    function test_Transfer_WhenProve() public {
        uint256 transferAmount = STAKER_PROVE_AMOUNT;
        uint256 currentBalance = ERC20(PROVE).balanceOf(STAKER_2);

        vm.prank(STAKER_1);
        bool success = ERC20(PROVE).transfer(STAKER_2, transferAmount);
        assertTrue(success);

        assertEq(ERC20(PROVE).balanceOf(STAKER_2), currentBalance + transferAmount);
    }

    function test_RevertTransfer_WheniPROVE() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Try to transfer iPROVE
        vm.expectRevert(abi.encodeWithSelector(IIntermediateSuccinct.NonTransferable.selector));
        vm.prank(STAKER_1);
        bool success = ERC20(I_PROVE).transfer(OWNER, stakeAmount);
        assertFalse(success);
    }

    function test_RevertTransfer_WhenPROVER() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Try to transfer $PROVER-N
        vm.expectRevert(abi.encodeWithSelector(IIntermediateSuccinct.NonTransferable.selector));
        vm.prank(STAKER_1);
        bool success = ERC20(ALICE_PROVER).transfer(OWNER, stakeAmount);
        assertFalse(success);
    }

    function test_RevertTransfer_WhenstPROVE() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Try to transfer stPROVE
        vm.expectRevert(abi.encodeWithSelector(IIntermediateSuccinct.NonTransferable.selector));
        vm.prank(STAKER_1);
        bool success = ERC20(STAKING).transfer(OWNER, stakeAmount);
        assertFalse(success);
    }

    function test_RevertDeposit_WhenDirectiPROVE() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Approve the I_PROVE vault to transfer $PROVE
        vm.prank(STAKER_1);
        ERC20(PROVE).approve(I_PROVE, stakeAmount);

        // Try to deposit directly into the I_PROVE vault
        vm.expectRevert(abi.encodeWithSelector(IIntermediateSuccinct.NonTransferable.selector));
        vm.prank(STAKER_1);
        IERC4626(I_PROVE).deposit(stakeAmount, STAKER_1);
    }

    function test_RevertMint_WhenDirectiPROVE() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Approve the I_PROVE vault to transfer $PROVE
        vm.prank(STAKER_1);
        ERC20(PROVE).approve(I_PROVE, stakeAmount);

        // Try to deposit directly into the I_PROVE vault
        vm.expectRevert(abi.encodeWithSelector(IIntermediateSuccinct.NonTransferable.selector));
        vm.prank(STAKER_1);
        IERC4626(I_PROVE).mint(stakeAmount, STAKER_1);
    }

    function test_RevertWithdraw_WhenDirectiPROVEFromStaker() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Alice prover approves STAKER_1 to withdraw from the I_PROVE vault
        vm.prank(ALICE_PROVER);
        ERC20(I_PROVE).approve(STAKER_1, stakeAmount);

        // Try to withdraw directly from the I_PROVE vault
        vm.expectRevert(abi.encodeWithSelector(IIntermediateSuccinct.NonTransferable.selector));
        vm.prank(STAKER_1);
        IERC4626(I_PROVE).withdraw(stakeAmount, STAKER_1, ALICE_PROVER);
    }

    function test_RevertRedeem_WhenDirectiPROVERFromStaker() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Alice prover approves STAKER_1 to withdraw from the I_PROVE vault
        vm.prank(ALICE_PROVER);
        ERC20(I_PROVE).approve(STAKER_1, stakeAmount);

        // Try to redeem directly from the I_PROVE vault
        vm.expectRevert(abi.encodeWithSelector(IIntermediateSuccinct.NonTransferable.selector));
        vm.prank(STAKER_1);
        IERC4626(I_PROVE).redeem(stakeAmount, STAKER_1, ALICE_PROVER);
    }

    function test_RevertWithdraw_WhenDirectiPROVEFromProver() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Try to withdraw directly from the I_PROVE vault. Technically the prover being able to
        // call this independantly should happen anyway (because we deploy the code for them).
        vm.expectRevert(abi.encodeWithSelector(IIntermediateSuccinct.NonTransferable.selector));
        vm.prank(ALICE_PROVER);
        IERC4626(I_PROVE).withdraw(stakeAmount, STAKER_1, ALICE_PROVER);
    }

    function test_RevertRedeem_WhenDirectiPROVEFromProver() public {
        uint256 stakeAmount = STAKER_PROVE_AMOUNT;

        // Stake to Alice prover
        _stake(STAKER_1, ALICE_PROVER, stakeAmount);

        // Try to redeem directly from the I_PROVE vault. Technically the prover being able to
        // call this independantly should happen anyway (because we deploy the code for them).
        vm.expectRevert(abi.encodeWithSelector(IIntermediateSuccinct.NonTransferable.selector));
        vm.prank(ALICE_PROVER);
        IERC4626(I_PROVE).redeem(stakeAmount, STAKER_1, ALICE_PROVER);
    }
}
