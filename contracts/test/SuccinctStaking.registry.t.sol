// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {IProver} from "../src/interfaces/IProver.sol";
import {IProverRegistry} from "../src/interfaces/IProverRegistry.sol";
import {ERC20} from "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract SuccinctStakingRegistryTests is SuccinctStakingTest {
    function test_CreateProver_WhenValid() public {
        address proverOwner = makeAddr("PROVER_OWNER");

        vm.prank(proverOwner);
        (address prover, uint256 stPROVE) = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS, PROVER_PROVE_AMOUNT);

        assertEq(IProver(prover).owner(), proverOwner);
        assertEq(IProver(prover).id(), 3);
        assertEq(ERC20(prover).name(), "SuccinctProver-3");
        assertEq(ERC20(prover).symbol(), "PROVER-3");
    }

    function test_RevertCreateProver_WhenAlreadyCreated() public {
        address proverOwner = makeAddr("PROVER_OWNER");

        vm.prank(proverOwner);
        (address prover, uint256 stPROVE) = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS, PROVER_PROVE_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IProverRegistry.ProverAlreadyExists.selector));
        vm.prank(proverOwner);
        (prover, stPROVE) = SuccinctStaking(STAKING).createProver(STAKER_FEE_BIPS, PROVER_PROVE_AMOUNT);
    }
}
