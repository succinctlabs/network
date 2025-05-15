// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctProver} from "../../src/tokens/SuccinctProver.sol";

contract SuccinctProverScript is BaseScript {
    string internal constant KEY = "PROVER";

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address I_PROVE = readAddress("I_PROVE");
        address STAKING = readAddress("STAKING");
        address OWNER = readAddress("OWNER");
        uint256 ID = 0;

        // Deploy contract
        SuccinctProver deployed = new SuccinctProver{salt: salt}(I_PROVE, STAKING, ID, OWNER);

        // Write address
        writeAddress(KEY, address(deployed));
    }
}
