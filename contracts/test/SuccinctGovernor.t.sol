// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {SuccinctGovernor} from "../src/SuccinctGovernor.sol";
import {SuccinctProver} from "../src/tokens/SuccinctProver.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IVotes} from "../lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "../lib/openzeppelin-contracts/contracts/governance/IGovernor.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract SuccinctGovernorTest is SuccinctStakingTest {
    function setUp() public virtual override {
        super.setUp();

        // Set the governor as the owner of SuccinctStaking contract.
        vm.prank(OWNER);
        SuccinctStaking(STAKING).transferOwnership(GOVERNOR);
    }

    function test_Propose_WhenValid() public {
        // The parameter to be updated.
        uint256 newDispenseRate = DISPENSE_RATE * 2;

        // Check Alice's prover's voting power before staking.
        uint256 votingPower = IVotes(I_PROVE).getVotes(ALICE_PROVER);
        assertEq(votingPower, IERC20(I_PROVE).balanceOf(ALICE_PROVER));

        // Staker stakes to Alice's prover.
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // It takes a block for voting power to update.
        vm.roll(block.number + 1);

        // Check Alice's prover's voting power after staking.
        votingPower = IVotes(I_PROVE).getVotes(ALICE_PROVER);
        assertEq(votingPower, IERC20(I_PROVE).balanceOf(ALICE_PROVER));

        // Alice makes a proposal through her prover contract.
        address[] memory targets = new address[](1);
        targets[0] = STAKING;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] =
            abi.encodeWithSelector(SuccinctStaking.updateDispenseRate.selector, newDispenseRate);
        string memory description =
            string.concat("Update dispense rate to ", Strings.toString(newDispenseRate));
        bytes32 descriptionHash = keccak256(bytes(description));

        // Alice proposes through her prover contract.
        vm.prank(ALICE);
        uint256 proposalId =
            SuccinctProver(ALICE_PROVER).propose(targets, values, calldatas, description);

        // Proposal should be in Pending state
        IGovernor.ProposalState state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Pending));

        // Wait for the voting delay.
        vm.roll(block.number + SuccinctGovernor(payable(GOVERNOR)).votingDelay() + 1);

        // Proposal should be in Active state.
        state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Active));

        // Alice votes FOR the proposal through her prover contract.
        vm.prank(ALICE);
        SuccinctProver(ALICE_PROVER).castVote(proposalId, 1);

        // Wait for the voting period.
        vm.roll(block.number + SuccinctGovernor(payable(GOVERNOR)).votingPeriod() + 1);

        // Proposal should be in Succeeded state (not Queued, since this governor doesn't have a timelock).
        state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Succeeded));

        // Execute the proposal.
        SuccinctGovernor(payable(GOVERNOR)).execute(targets, values, calldatas, descriptionHash);

        // Proposal should be in Executed state
        state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Executed));

        // Verify the dispense rate was updated.
        assertEq(SuccinctStaking(STAKING).dispenseRate(), newDispenseRate);
    }
}
