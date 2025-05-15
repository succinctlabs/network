// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {Succinct} from "../../src/tokens/Succinct.sol";

contract SuccinctScript is BaseScript {
    string internal constant KEY = "PROVE";

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address OWNER = readAddress("OWNER");

        // Deploy contract
        Succinct deployed = new Succinct{salt: salt}(OWNER);

        // Write address
        writeAddress(KEY, address(deployed));
    }
}
