// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctGovernor} from "../../src/SuccinctGovernor.sol";

contract SuccinctGovernorScript is BaseScript {
    string internal constant KEY = "GOVERNOR";

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address I_PROVE = readAddress("I_PROVE");
        uint48 VOTING_DELAY = readUint48("VOTING_DELAY");
        uint32 VOTING_PERIOD = readUint32("VOTING_PERIOD");
        uint256 PROPOSAL_THRESHOLD = readUint256("PROPOSAL_THRESHOLD");
        uint256 QUORUM_FRACTION = readUint256("QUORUM_FRACTION");

        // Deploy contract
        SuccinctGovernor deployed = new SuccinctGovernor{salt: salt}(
            I_PROVE, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD, QUORUM_FRACTION
        );

        // Write address
        writeAddress(KEY, address(deployed));
    }
}
