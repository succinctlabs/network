// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {SuccinctGovernor} from "../src/SuccinctGovernor.sol";
import {SuccinctProver} from "../src/tokens/SuccinctProver.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IVotes} from "../lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";

contract SuccinctGovernorTest is SuccinctStakingTest {
    function setUp() public virtual override {
        super.setUp();

        // Set the governor as the owner of SuccinctStaking contract
        vm.prank(OWNER);
        SuccinctStaking(STAKING).transferOwnership(GOVERNOR);
    }

    function test_Propose_WhenValid() public {
        // Staker deposits to Alice $PROVER.
        vm.prank(STAKER_1);
        IERC20(PROVE).approve(STAKING, STAKER_PROVE_AMOUNT);
        vm.prank(STAKER_1);
        SuccinctStaking(STAKING).stake(ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // Alice (prover owner) makes a proposal through her prover contract.
        address[] memory targets = new address[](1);
        targets[0] = STAKING;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] =
            abi.encodeWithSelector(SuccinctStaking.updateDispenseRate.selector, DISPENSE_RATE * 2);
        string memory description = "Update dispense rate to twice the current rate";

        // Check voting power (iPROVE balance of Alice's prover)
        uint256 votingPower = IVotes(I_PROVE).getVotes(ALICE_PROVER);
        console.log("Alice prover voting power:", votingPower);

        vm.roll(block.number + 1); // Move forward one block

        // Alice proposes through her prover contract
        vm.prank(ALICE);
        SuccinctProver(ALICE_PROVER).propose(targets, values, calldatas, description);

        // Check the governor contract to ensure the proposal was created
        // The proposal exists if we can get its state without reverting
        uint256 proposalId = SuccinctGovernor(payable(GOVERNOR)).hashProposal(
            targets, values, calldatas, keccak256(bytes(description))
        );

        // Proposal should be in Pending state (0)
        assertEq(uint256(SuccinctGovernor(payable(GOVERNOR)).state(proposalId)), 0);
    }

    // TODO execute
}
