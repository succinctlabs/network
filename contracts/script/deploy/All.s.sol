// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {IntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";
import {SuccinctGovernor} from "../../src/SuccinctGovernor.sol";
import {Succinct} from "../../src/tokens/Succinct.sol";
import {FixtureLoader} from "../../test/utils/FixtureLoader.sol";
import {ERC1967Proxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SP1VerifierGateway} from "../../lib/sp1-contracts/contracts/src/SP1VerifierGateway.sol";
import {SP1Verifier} from "../../lib/sp1-contracts/contracts/src/v4.0.0-rc.3/SP1VerifierGroth16.sol";

// Deploy all contracts.
contract AllScript is BaseScript, FixtureLoader {
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
        address I_PROVE = address(new IntermediateSuccinct{salt: salt}(PROVE, STAKING));
        (address VERIFIER, address VAPP) = _deployVAppAsProxy(salt, OWNER, PROVE, I_PROVE, STAKING);
        address GOVERNOR = address(new SuccinctGovernor{salt: salt}(STAKING));

        // Initialize staking contract
        SuccinctStaking(STAKING).initialize(
            VAPP, PROVE, I_PROVE, MIN_STAKE_AMOUNT, UNSTAKE_PERIOD, SLASH_PERIOD, DISPENSE_RATE
        );

        // Write addresses
        writeAddress("STAKING", STAKING);
        writeAddress("VERIFIER", VERIFIER);
        writeAddress("VAPP", VAPP);
        writeAddress("PROVE", PROVE);
        writeAddress("I_PROVE", I_PROVE);
        writeAddress("GOVERNOR", GOVERNOR);
    }

    /// @dev This is a stack-too-deep workaround.
    function _deployVAppAsProxy(bytes32 salt, address OWNER, address PROVE, address I_PROVE, address STAKING)
        internal
        returns (address, address)
    {
        // Read config
        address VERIFIER = vm.envOr("VERIFIER", address(0));
        bytes32 VKEY = bytes32(0x0027860ee5a98f9ad361de3622d6eaf4a9caf2c2354395332fc95254eddab0f6);
        bytes32 GENESIS_STATE_ROOT =
            bytes32(0x4b15a7d34ea0ec471d0d6ab9170cc2910f590819ee168e2a799e25244e327116);
        uint64 GENESIS_TIMESTAMP = 0;

        if (VERIFIER == address(0)) {
            // Deploy the SP1VerifierGatway
            VERIFIER = address(new SP1VerifierGateway{salt: salt}(OWNER));
            address groth16 = address(new SP1Verifier{salt: salt}());
            SP1VerifierGateway(VERIFIER).addRoute(groth16);
        }

        // Deploy contract
        address vappImpl = address(new SuccinctVApp{salt: salt}());
        address VAPP =
            address(SuccinctVApp(payable(address(new ERC1967Proxy{salt: salt}(vappImpl, "")))));
        SuccinctVApp(VAPP).initialize(
            msg.sender, PROVE, I_PROVE, STAKING, VERIFIER, VKEY, GENESIS_STATE_ROOT, GENESIS_TIMESTAMP
        );

        return (VERIFIER, VAPP);
    }
}

//     at bin/vapp/src/main.rs:79

//   2025-06-07T01:20:49.943576Z  INFO spn_vapp::driver: stf vkey bytes32: "0x0071c8d938846d01d3b3ef216192c1848be9077c74ce0a32c95e7c703b8c442a"
//     at bin/vapp/src/driver.rs:142

//   2025-06-07T01:20:50.462312Z  INFO spn_vapp::driver: aggregation vkey bytes32: "0x0027860ee5a98f9ad361de3622d6eaf4a9caf2c2354395332fc95254eddab0f6"
//     at bin/vapp/src/driver.rs:146

//   2025-06-07T01:20:50.462474Z  INFO spn_vapp::driver: genesis state root: 0x4b15a7d34ea0ec471d0d6ab9170cc2910f590819ee168e2a799e25244e327116
//     at bin/vapp/src/driver.rs:158

//   2025-06-07T01:20:50.647385Z  INFO spn_vapp::driver: Initialized with genesis state 4b15a7d34ea0ec471d0d6ab9170cc2910f590819ee168e2a799e25244e327116 at cursor 1
//     at bin/vapp/src/driver.rs:348
