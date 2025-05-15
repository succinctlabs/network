// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {IntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";

contract IntermediateSuccinctScript is BaseScript {
    string internal constant KEY = "I_PROVE";

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address PROVE = readAddress("PROVE");
        address STAKING = readAddress("STAKING");

        // Deploy contract
        IntermediateSuccinct deployed = new IntermediateSuccinct{salt: salt}(PROVE, STAKING);

        // Write address
        writeAddress(KEY, address(deployed));
    }
}
