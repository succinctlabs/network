// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {MockVApp} from "../../src/mocks/MockVApp.sol";

contract VAPPScript is BaseScript {
    string internal constant KEY = "VAPP";

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address STAKING = readAddress("STAKING");
        address USDC = readAddress("USDC");

        // Deploy contract
        MockVApp deployed = new MockVApp{salt: salt}(STAKING, USDC);

        // Write address
        writeAddress(KEY, address(deployed));
    }
}
