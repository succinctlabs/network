// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {IntermediateSuccinct} from "../../src/tokens/IntermediateSuccinct.sol";
import {SuccinctGovernor} from "../../src/SuccinctGovernor.sol";
import {MockVApp} from "../../src/mocks/MockVApp.sol";
import {Succinct} from "../../src/tokens/Succinct.sol";

// Deploy all contracts.
contract AllScript is BaseScript {
    function run() external broadcaster {
        // Read config
        bytes32 CREATE2_SALT = readBytes32("CREATE2_SALT");
        address OWNER = readAddress("OWNER");
        uint256 MIN_STAKE_AMOUNT = readUint256("MIN_STAKE_AMOUNT");
        uint256 UNSTAKE_PERIOD = readUint256("UNSTAKE_PERIOD");
        uint256 SLASH_PERIOD = readUint256("SLASH_PERIOD");
        uint256 DISPENSE_RATE = readUint256("DISPENSE_RATE");

        // Deploy contracts
        address STAKING = address(new SuccinctStaking{salt: CREATE2_SALT}(OWNER));
        address PROVE = address(new Succinct{salt: CREATE2_SALT}(OWNER));
        address VAPP = address(new MockVApp{salt: CREATE2_SALT}(STAKING, PROVE));
        address I_PROVE = address(new IntermediateSuccinct{salt: CREATE2_SALT}(PROVE, STAKING));
        address GOVERNOR = address(new SuccinctGovernor{salt: CREATE2_SALT}(I_PROVE));

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
}
