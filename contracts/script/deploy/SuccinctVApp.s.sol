// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {FixtureLoader, SP1ProofFixtureJson, Fixture} from "../../test/utils/FixtureLoader.sol";

// TODO: Make this upgradable

contract SuccinctVAppScript is BaseScript, FixtureLoader {
    string internal constant KEY = "VAPP";

    // Get from the corresponding chain here: 
    // https://github.com/succinctlabs/sp1-contracts/tree/main/contracts/deployments
    address internal SP1_VERIFIER_GATEWAY_GROTH16 = 0x397A5f7f3dBd538f23DE225B51f532c34448dA9B;

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address STAKING = readAddress("STAKING");
        address WETH = readAddress("WETH");
        address USDC = readAddress("USDC");
        address PROVE = readAddress("PROVE");
        address VERIFIER = SP1_VERIFIER_GATEWAY_GROTH16;

        SP1ProofFixtureJson memory fixture = loadFixture(vm, Fixture.Groth16);
        bytes32 vkey = fixture.vkey;

        // Deploy contract
        SuccinctVApp vapp = new SuccinctVApp{salt: salt}();
        vapp.initialize(msg.sender, WETH, USDC, PROVE, STAKING, VERIFIER, vkey);
        vapp.addToken(PROVE);

        // Write address
        writeAddress(KEY, address(vapp));
    }
}
