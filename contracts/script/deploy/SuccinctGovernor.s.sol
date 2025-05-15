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

        // Deploy contract
        SuccinctGovernor deployed = new SuccinctGovernor{salt: salt}(I_PROVE);

        // Write address
        writeAddress(KEY, address(deployed));
    }
}
