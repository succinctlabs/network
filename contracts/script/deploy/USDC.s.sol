// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";

contract USDCScript is BaseScript {
    string internal constant KEY = "USDC";

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");

        // Deploy contract
        MockUSDC deployed = new MockUSDC{salt: salt}();

        // Write address
        writeAddress(KEY, address(deployed));
    }
}
