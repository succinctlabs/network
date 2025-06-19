// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from
    "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from
    "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

string constant NAME = "SuccinctGovernor";
uint48 constant VOTING_DELAY = 7200; // 1 day
uint32 constant VOTING_PERIOD = 50400; // 1 week
uint256 constant PROPOSAL_THRESHOLD = 100_000e18; // 100,000 tokens minimum to propose
uint256 constant QUORUM_FRACTION = 4; // 4% of total supply required to pass a proposal

/// @title SuccinctGovernor
/// @author Succinct Labs
/// @notice Governor for governance operations in the Succinct Prover Network.
/// @dev This contract should only be made owner of the relevant contracts (e.g. SuccinctStaking)
///      once sufficient staking (minting of $iPROVE) has occurred.
contract SuccinctGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction
{
    constructor(address _token)
        Governor(NAME)
        GovernorSettings(VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD)
        GovernorVotes(IVotes(_token))
        GovernorVotesQuorumFraction(QUORUM_FRACTION)
    {}

    // The following functions are overrides required by Solidity.

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function quorum(uint256 _blockNumber)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(_blockNumber);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }
}
