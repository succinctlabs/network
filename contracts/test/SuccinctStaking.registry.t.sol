// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {IProver} from "../src/interfaces/IProver.sol";
import {IProverRegistry} from "../src/interfaces/IProverRegistry.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

contract SuccinctStakingRegistryTests is SuccinctStakingTest {
    function test_CreateProver_WhenValid() public {
        address proverOwner = makeAddr("PROVER_OWNER");

        vm.prank(proverOwner);
        address prover = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);

        assertEq(IProver(prover).owner(), proverOwner);
        assertEq(IProver(prover).id(), 3);
        assertEq(ERC20(prover).name(), "SuccinctProver-3");
        assertEq(ERC20(prover).symbol(), "PROVER-3");
    }

    function test_RevertCreateProver_WhenAlreadyCreated() public {
        address proverOwner = makeAddr("PROVER_OWNER");

        vm.prank(proverOwner);
        SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);

        vm.expectRevert(abi.encodeWithSelector(IProverRegistry.ProverAlreadyExists.selector));
        vm.prank(proverOwner);
        SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);
    }

    function testFuzz_CreateProver_WhenWithVariableFees(uint256 _stakerFeeBips) public {
        uint256 stakerFeeBips = bound(_stakerFeeBips, 0, FEE_UNIT); // 0 to 100%
        address proverOwner = makeAddr("PROVER_OWNER");

        vm.prank(proverOwner);
        address prover = SuccinctStaking(STAKING).createProver(stakerFeeBips);

        // Verify prover creation
        assertEq(IProver(prover).owner(), proverOwner);
        assertEq(IProver(prover).stakerFeeBips(), stakerFeeBips);

        // Stake to the prover to ensure it works
        _stake(STAKER_1, prover, MIN_STAKE_AMOUNT);
        assertEq(SuccinctStaking(STAKING).proverStaked(prover), MIN_STAKE_AMOUNT);
    }

    function testFuzz_CreateProver_WhenMultipleProvers(uint8 _numProvers) public {
        uint256 numProvers = bound(uint256(_numProvers), 1, 10);
        address[] memory provers = new address[](numProvers);

        for (uint256 i = 0; i < numProvers; i++) {
            address proverOwner = makeAddr(string.concat("OWNER_", vm.toString(i)));
            uint256 feeBips = (i * FEE_UNIT) / numProvers; // Varying fees

            vm.prank(proverOwner);
            provers[i] = SuccinctStaking(STAKING).createProver(feeBips);

            // Verify each prover
            assertEq(IProver(provers[i]).owner(), proverOwner);
            assertEq(IProver(provers[i]).stakerFeeBips(), feeBips);
            assertEq(IProver(provers[i]).id(), i + 3); // Starting from 3 because of setup provers
        }

        // Verify all provers are different
        for (uint256 i = 0; i < numProvers; i++) {
            for (uint256 j = i + 1; j < numProvers; j++) {
                assertTrue(provers[i] != provers[j], "Provers should be unique");
            }
        }
    }

    function testFuzz_CreateProver_WhenProverOwnershipAndStaking(
        address _proverOwner,
        address _staker,
        uint256 _stakeAmount
    ) public {
        vm.assume(_proverOwner != address(0));
        vm.assume(_staker != address(0));
        vm.assume(_proverOwner != _staker);
        // Ensure these addresses don't already have provers
        vm.assume(SuccinctStaking(STAKING).getProver(_proverOwner) == address(0));
        vm.assume(_staker != ALICE && _staker != BOB); // These already have provers from setup

        uint256 stakeAmount = bound(_stakeAmount, MIN_STAKE_AMOUNT, STAKER_PROVE_AMOUNT);

        // Create prover
        vm.prank(_proverOwner);
        address prover = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS);

        // Setup staker
        deal(PROVE, _staker, stakeAmount);

        // Stake to prover
        vm.prank(_staker);
        IERC20(PROVE).approve(STAKING, stakeAmount);
        vm.prank(_staker);
        SuccinctStaking(STAKING).stake(prover, stakeAmount);

        // Verify ownership and staking
        assertEq(IProver(prover).owner(), _proverOwner);
        assertEq(SuccinctStaking(STAKING).stakedTo(_staker), prover);
        assertEq(SuccinctStaking(STAKING).staked(_staker), stakeAmount);
    }
}
