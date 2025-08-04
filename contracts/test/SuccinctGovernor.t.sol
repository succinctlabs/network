// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctStakingTest} from "./SuccinctStaking.t.sol";
import {SuccinctStaking} from "../src/SuccinctStaking.sol";
import {SuccinctGovernor} from "../src/SuccinctGovernor.sol";
import {SuccinctProver} from "../src/tokens/SuccinctProver.sol";
import {IProver} from "../src/interfaces/IProver.sol";
import {ISuccinctStaking} from "../src/interfaces/ISuccinctStaking.sol";
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IVotes} from "../lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol";
import {IGovernor} from "../lib/openzeppelin-contracts/contracts/governance/IGovernor.sol";
import {Strings} from "../lib/openzeppelin-contracts/contracts/utils/Strings.sol";

// These tests aim to only cover our governance-specific changes (e.g. voting through the prover
// utilizing $iPROVE as the votes token). For general Votes<->Governor interaction, it is assumed
// OpenZepplin's implementations are correct.
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
        vm.warp(block.timestamp + 1);
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
        vm.warp(block.timestamp + SuccinctGovernor(payable(GOVERNOR)).votingDelay() + 1);
        vm.roll(block.number + 1);

        // Proposal should be in Active state.
        state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Active));

        // Check the votes before Alice votes.
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) =
            SuccinctGovernor(payable(GOVERNOR)).proposalVotes(proposalId);
        assertEq(forVotes, 0);
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);

        // Alice votes FOR the proposal through her prover contract.
        vm.prank(ALICE);
        SuccinctProver(ALICE_PROVER).castVote(proposalId, 1);

        // Check the votes after Alice votes.
        (againstVotes, forVotes, abstainVotes) =
            SuccinctGovernor(payable(GOVERNOR)).proposalVotes(proposalId);
        assertEq(forVotes, IERC20(I_PROVE).balanceOf(ALICE_PROVER));
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);

        // Wait for the voting period.
        vm.warp(block.timestamp + SuccinctGovernor(payable(GOVERNOR)).votingPeriod() + 1);
        vm.roll(block.number + 1);

        // Proposal should be in Succeeded state (not Queued, since this governor doesn't have a timelock).
        state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Succeeded));

        // Execute the proposal (anyone can execute a proposal).
        vm.prank(STAKER_1);
        SuccinctGovernor(payable(GOVERNOR)).execute(targets, values, calldatas, descriptionHash);

        // Proposal should be in Executed state
        state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Executed));

        // Verify the dispense rate was updated.
        assertEq(SuccinctStaking(STAKING).dispenseRate(), newDispenseRate);
    }

    // Only the prover owner can make a proposal through the prover.
    function test_RevertPropose_WhenNotProverOwner() public {
        // The parameter to be updated.
        uint256 newDispenseRate = DISPENSE_RATE * 2;

        // Staker stakes to Alice's prover.
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // It takes a block for voting power to update.
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

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

        // Alice proposes through her prover contract.
        vm.expectRevert(abi.encodeWithSelector(IProver.NotProverOwner.selector));
        vm.prank(STAKER_1);
        SuccinctProver(ALICE_PROVER).propose(targets, values, calldatas, description);
    }

    // A prover can only make a proposal if their voting power (I_PROVE balance) is
    // >= SuccinctGovernor.proposalThreshold().
    function test_RevertPropose_WhenNotEnoughVotingPower() public {
        // The parameter to be updated.
        uint256 newDispenseRate = DISPENSE_RATE * 2;

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

        // Alice proposes through her prover contract.
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorInsufficientProposerVotes.selector,
                ALICE_PROVER,
                IERC20(I_PROVE).balanceOf(ALICE_PROVER),
                SuccinctGovernor(payable(GOVERNOR)).proposalThreshold()
            )
        );
        vm.prank(ALICE);
        SuccinctProver(ALICE_PROVER).propose(targets, values, calldatas, description);
    }

    // A prover owner can cancel their own proposal if it is still pending.
    function test_Cancel_WhenValid() public {
        // The parameter to be updated.
        uint256 newDispenseRate = DISPENSE_RATE * 2;

        // Staker stakes to Alice's prover.
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // It takes a block for voting power to update.
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

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

        // Proposal should be in Pending state.
        IGovernor.ProposalState state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Pending));

        // Alice cancels the proposal through her prover contract.
        vm.prank(ALICE);
        SuccinctProver(ALICE_PROVER).cancel(targets, values, calldatas, descriptionHash);

        // Proposal should be in Canceled state.
        state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Canceled));
    }

    // Only the prover owner can cancel a proposal through the prover.
    function test_RevertCancel_WhenNotProverOwner() public {
        // The parameter to be updated.
        uint256 newDispenseRate = DISPENSE_RATE * 2;

        // Staker stakes to Alice's prover.
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // It takes a block for voting power to update.
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

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

        // Bob (non-owner) tries to cancel Alice's proposal through her prover contract.
        vm.expectRevert(abi.encodeWithSelector(IProver.NotProverOwner.selector));
        vm.prank(BOB);
        SuccinctProver(ALICE_PROVER).cancel(targets, values, calldatas, descriptionHash);

        // Proposal should still be in Pending state.
        IGovernor.ProposalState state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Pending));
    }

    // Only the prover owner can cast a vote through the prover.
    function test_RevertCastVote_WhenNotProverOwner() public {
        // The parameter to be updated.
        uint256 newDispenseRate = DISPENSE_RATE * 2;

        // Staker stakes to Alice's prover.
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);

        // It takes a block for voting power to update.
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

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

        // Alice proposes through her prover contract.
        vm.prank(ALICE);
        uint256 proposalId =
            SuccinctProver(ALICE_PROVER).propose(targets, values, calldatas, description);

        // Wait for the voting delay.
        vm.warp(block.timestamp + SuccinctGovernor(payable(GOVERNOR)).votingDelay() + 1);
        vm.roll(block.number + 1);

        // Proposal should be in Active state.
        IGovernor.ProposalState state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Active));

        // Bob (non-owner) tries to vote through Alice's prover contract.
        vm.expectRevert(abi.encodeWithSelector(IProver.NotProverOwner.selector));
        vm.prank(BOB);
        SuccinctProver(ALICE_PROVER).castVote(proposalId, 1);

        // Check that no vote was recorded.
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) =
            SuccinctGovernor(payable(GOVERNOR)).proposalVotes(proposalId);
        assertEq(forVotes, 0);
        assertEq(againstVotes, 0);
        assertEq(abstainVotes, 0);
    }

    // Tests that slash indices remain stable when executing governance proposals and that
    // governance can properly target specific slash requests even with concurrent finishing
    // or slashing operations.
    function test_Execute_WhenSlashNoIndexShift() public {
        // Stake to both provers.
        _stake(STAKER_1, ALICE_PROVER, STAKER_PROVE_AMOUNT);
        _stake(STAKER_2, BOB_PROVER, STAKER_PROVE_AMOUNT);

        // Request two slashes for ALICE_PROVER.
        _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT);
        _requestSlash(ALICE_PROVER, STAKER_PROVE_AMOUNT / 2);

        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // Bob makes a proposal to cancel the first slash for ALICE_PROVER.
        address[] memory targets = new address[](1);
        targets[0] = STAKING;
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(SuccinctStaking.cancelSlash.selector, ALICE_PROVER, 0);
        string memory description =
            string.concat("Cancel Slash for ", Strings.toString(uint160(ALICE_PROVER)));
        bytes32 descriptionHash = keccak256(bytes(description));

        // Bob proposes through her prover contract.
        vm.prank(BOB);
        uint256 proposalId =
            SuccinctProver(BOB_PROVER).propose(targets, values, calldatas, description);

        // Wait for the voting delay.
        vm.warp(block.timestamp + SuccinctGovernor(payable(GOVERNOR)).votingDelay() + 1);
        vm.roll(block.number + 1);

        // Proposal should be in Active state.
        IGovernor.ProposalState state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Active));

        // Bob makes another proposal to finish the second slash for ALICE_PROVER.
        address[] memory targets1 = new address[](1);
        targets1[0] = STAKING;
        uint256[] memory values1 = new uint256[](1);
        values1[0] = 0;
        bytes[] memory calldatas1 = new bytes[](1);
        calldatas1[0] =
            abi.encodeWithSelector(SuccinctStaking.finishSlash.selector, ALICE_PROVER, 1);
        string memory description1 =
            string.concat("Finish Slash for ", Strings.toString(uint160(ALICE_PROVER)));
        bytes32 descriptionHash1 = keccak256(bytes(description1));

        // Bob proposes through his prover contract.
        vm.prank(BOB);
        uint256 proposalId1 =
            SuccinctProver(BOB_PROVER).propose(targets1, values1, calldatas1, description1);

        // Wait for the voting delay.
        vm.warp(block.timestamp + SuccinctGovernor(payable(GOVERNOR)).votingDelay() + 1);
        vm.roll(block.number + 1);

        // Proposal should be in Active state.
        IGovernor.ProposalState state1 = SuccinctGovernor(payable(GOVERNOR)).state(proposalId1);
        assertEq(uint8(state1), uint8(IGovernor.ProposalState.Active));

        // Bob votes FOR the first proposal (cancel the first slash).
        vm.prank(BOB);
        SuccinctProver(BOB_PROVER).castVote(proposalId, 1);

        // Wait for the voting period.
        vm.warp(block.timestamp + SuccinctGovernor(payable(GOVERNOR)).votingPeriod() - 20);
        vm.roll(block.number + 1);

        // Bob votes FOR the second proposal.
        vm.prank(BOB);
        SuccinctProver(BOB_PROVER).castVote(proposalId1, 1);

        vm.warp(block.timestamp + 20 + 1);
        vm.roll(block.number + 1);

        // First proposal should be in Succeeded state.
        state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Succeeded));

        // Alice has two slash requests before executing.
        assertEq(SuccinctStaking(STAKING).slashRequests(ALICE_PROVER).length, 2);

        // Wait for the cancellation deadline to pass.
        vm.warp(block.timestamp + SLASH_CANCELLATION_PERIOD + VOTING_DELAY + VOTING_PERIOD);

        // Execute the first proposal (cancel slash at index 0).
        vm.prank(STAKER_1);
        SuccinctGovernor(payable(GOVERNOR)).execute(targets, values, calldatas, descriptionHash);

        // Alice still has two slash requests after execution (resolved flag used, not removed).
        assertEq(SuccinctStaking(STAKING).slashRequests(ALICE_PROVER).length, 2);

        // First proposal should be in Executed state.
        state = SuccinctGovernor(payable(GOVERNOR)).state(proposalId);
        assertEq(uint8(state), uint8(IGovernor.ProposalState.Executed));

        // Wait for next block.
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // Second proposal should be in Succeeded state.
        state1 = SuccinctGovernor(payable(GOVERNOR)).state(proposalId1);
        assertEq(uint8(state1), uint8(IGovernor.ProposalState.Succeeded));

        // Execute the second proposal (finish the second slash).
        vm.prank(STAKER_1);
        SuccinctGovernor(payable(GOVERNOR)).execute(targets1, values1, calldatas1, descriptionHash1);

        // Second proposal should be in Executed state.
        state1 = SuccinctGovernor(payable(GOVERNOR)).state(proposalId1);
        assertEq(uint8(state1), uint8(IGovernor.ProposalState.Executed));

        // Both slash requests should still exist but be resolved.
        assertEq(SuccinctStaking(STAKING).slashRequests(ALICE_PROVER).length, 2);

        // Verify both requests are resolved.
        ISuccinctStaking.SlashClaim[] memory requests =
            SuccinctStaking(STAKING).slashRequests(ALICE_PROVER);
        assertTrue(requests[0].resolved);
        assertTrue(requests[1].resolved);
    }
}
