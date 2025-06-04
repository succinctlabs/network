// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {FixtureLoader, SP1ProofFixtureJson, Fixture} from "../../test/utils/FixtureLoader.sol";
import {ERC1967Proxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SuccinctVAppScript is BaseScript, FixtureLoader {
    string internal constant KEY = "VAPP";

    // Get from the corresponding chain deployment here:
    // https://github.com/succinctlabs/sp1-contracts/tree/main/contracts/deployments
    address internal SP1_VERIFIER_GATEWAY_GROTH16 = 0x397A5f7f3dBd538f23DE225B51f532c34448dA9B;

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address STAKING = readAddress("STAKING");
        address PROVE = readAddress("PROVE");
        address I_PROVE = readAddress("I_PROVE");
        address VERIFIER = SP1_VERIFIER_GATEWAY_GROTH16;
        address FEE_VAULT = readAddress("FEE_VAULT");
        uint64 MAX_ACTION_DELAY = readUint64("MAX_ACTION_DELAY");
        uint256 PROTOCOL_FEE_BIPS = readUint256("PROTOCOL_FEE_BIPS");

        // Load fixture
        SP1ProofFixtureJson memory fixture = loadFixture(vm, Fixture.Groth16);
        bytes32 VKEY = fixture.vkey;

        // Deploy contract
        address vappImpl = address(new SuccinctVApp{salt: salt}());
        address VAPP =
            address(SuccinctVApp(payable(address(new ERC1967Proxy{salt: salt}(vappImpl, "")))));
        SuccinctVApp(VAPP).initialize(
            msg.sender, PROVE, I_PROVE, STAKING, VERIFIER, VKEY, 0, bytes32(uint256(0)), 0
        );

        // Write address
        writeAddress(KEY, VAPP);
    }

    function upgrade() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address PROXY = readAddress(KEY);

        // Deploy contract
        address vappImpl = address(new SuccinctVApp{salt: salt}());
        SuccinctVApp(payable(PROXY)).upgradeToAndCall(address(vappImpl), "");

        // Proxy adress is still the same
    }
}
