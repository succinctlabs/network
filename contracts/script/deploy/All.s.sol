// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {IntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";
import {SuccinctGovernor} from "../../src/SuccinctGovernor.sol";
import {Succinct} from "../../src/tokens/Succinct.sol";
import {FixtureLoader, SP1ProofFixtureJson, Fixture} from "../../test/utils/FixtureLoader.sol";
import {ERC1967Proxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Deploy all contracts.
contract AllScript is BaseScript, FixtureLoader {
    // Get from the corresponding chain deployment here:
    // https://github.com/succinctlabs/sp1-contracts/tree/main/contracts/deployments
    address internal SP1_VERIFIER_GATEWAY_GROTH16 = 0x397A5f7f3dBd538f23DE225B51f532c34448dA9B;

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address OWNER = readAddress("OWNER");
        uint256 MIN_STAKE_AMOUNT = readUint256("MIN_STAKE_AMOUNT");
        uint256 UNSTAKE_PERIOD = readUint256("UNSTAKE_PERIOD");
        uint256 SLASH_PERIOD = readUint256("SLASH_PERIOD");
        uint256 DISPENSE_RATE = readUint256("DISPENSE_RATE");

        // Deploy contracts
        address STAKING = address(new SuccinctStaking{salt: salt}(OWNER));
        address PROVE = address(new Succinct{salt: salt}(OWNER));
        address VAPP = _deployVAppAsProxy(salt, PROVE, STAKING);
        address I_PROVE = address(new IntermediateSuccinct{salt: salt}(PROVE, STAKING));
        address GOVERNOR = address(new SuccinctGovernor{salt: salt}(I_PROVE));

        // Initialize contracts
        SuccinctStaking(STAKING).initialize(
            VAPP, PROVE, I_PROVE, MIN_STAKE_AMOUNT, UNSTAKE_PERIOD, SLASH_PERIOD, DISPENSE_RATE
        );

        // Write addresses
        writeAddress("STAKING", STAKING);
        writeAddress("VAPP", VAPP);
        writeAddress("PROVE", PROVE);
        writeAddress("I_PROVE", I_PROVE);
        writeAddress("GOVERNOR", GOVERNOR);
    }

    /// @dev This helper is mostly to avoid stack-too-deep.
    function _deployVAppAsProxy(bytes32 salt, address PROVE, address STAKING)
        internal
        returns (address)
    {
        // Read config
        address VERIFIER = SP1_VERIFIER_GATEWAY_GROTH16;
        uint64 MAX_ACTION_DELAY = readUint64("MAX_ACTION_DELAY");
        uint64 FREEZE_DURATION = readUint64("FREEZE_DURATION");

        // Load fixture
        SP1ProofFixtureJson memory fixture = loadFixture(vm, Fixture.Groth16);
        bytes32 VKEY = fixture.vkey;

        // Deploy contract
        address vappImpl = address(new SuccinctVApp{salt: salt}());
        address VAPP =
            address(SuccinctVApp(payable(address(new ERC1967Proxy{salt: salt}(vappImpl, "")))));
        SuccinctVApp(VAPP).initialize(
            msg.sender, PROVE, STAKING, VERIFIER, VKEY, MAX_ACTION_DELAY, FREEZE_DURATION
        );

        return VAPP;
    }
}
