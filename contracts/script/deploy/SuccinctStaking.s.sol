// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";

contract SuccinctStakingScript is BaseScript {
    string internal constant KEY = "STAKING";

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address OWNER = readAddress("OWNER");

        // Deploy contract
        SuccinctStaking deployed = new SuccinctStaking{salt: salt}(OWNER);

        // Write address
        writeAddress(KEY, address(deployed));
    }

    /// @dev Only run this once all of the other contracts are deployed. Script must be ran with OWNER's private key.
    function initialize() external broadcaster {
        address STAKING = readAddress(KEY);
        address VAPP = readAddress("VAPP");
        address PROVE = readAddress("PROVE");
        address USDC = readAddress("USDC");
        address I_PROVE = readAddress("I_PROVE");
        uint256 MIN_STAKE_AMOUNT = readUint256("MIN_STAKE_AMOUNT");
        uint256 UNSTAKE_PERIOD = readUint256("UNSTAKE_PERIOD");
        uint256 SLASH_PERIOD = readUint256("SLASH_PERIOD");
        uint256 DISPENSE_RATE = readUint256("DISPENSE_RATE");

        SuccinctStaking(STAKING).initialize(
            VAPP, PROVE, I_PROVE, MIN_STAKE_AMOUNT, UNSTAKE_PERIOD, SLASH_PERIOD, DISPENSE_RATE
        );
    }
}
