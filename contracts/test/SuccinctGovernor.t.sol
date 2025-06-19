// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {SuccinctProver} from "../src/tokens/SuccinctProver.sol";
import {ISuccinct} from "../src/interfaces/ISuccinct.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IVotes} from "../lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

contract SuccinctGovernorTest is SuccinctStakingTest {
    uint256 public constant STAKE_AMOUNT = 100_000e18;

    function setUp() public virtual override {
        super.setUp();

        // Set the governor as the owner of SuccinctStaking contract
        vm.prank(OWNER);
        SuccinctStaking(STAKING).transferOwnership(GOVERNOR);

        // Temp: mint the staker some more
        vm.prank(OWNER);
        ISuccinct(PROVE).mint(STAKER_1, STAKE_AMOUNT);
    }

    function test_propose() public {
        // Staker deposits to Alice $PROVER.
        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, STAKE_AMOUNT);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, STAKE_AMOUNT);

        // Alice (prover owner) makes a proposal through her prover contract.
        address[] memory targets = new address[](1);
        targets[0] = VAPP;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] =
            abi.encodeWithSelector(SuccinctStaking.updateDispenseRate.selector, DISPENSE_RATE * 2);
        string memory description = "Test proposal to update dispense rate";

        // Check voting power (iPROVE balance of Alice's prover)
        uint256 votingPower = IVotes(I_PROVE).getVotes(ALICE_PROVER);
        console.log("Alice prover voting power:", votingPower);

        vm.roll(block.number + 1); // Move forward one block

        // Alice proposes through her prover contract
        vm.prank(ALICE);
        SuccinctProver(ALICE_PROVER).propose(targets, values, calldatas, description);
    }

    // TODO execute
}
