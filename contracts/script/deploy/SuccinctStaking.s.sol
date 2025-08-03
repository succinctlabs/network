// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctStaking} from "../../src/SuccinctStaking.sol";
import {ERC1967Proxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SuccinctStakingScript is BaseScript {
    string internal constant KEY = "STAKING";

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address OWNER = readAddress("OWNER");
        address GOVERNOR = readAddress("GOVERNOR");
        address VAPP = readAddress("VAPP");
        address PROVE = readAddress("PROVE");
        address I_PROVE = readAddress("I_PROVE");
        address DISPENSER = readAddress("DISPENSER");
        uint256 MIN_STAKE_AMOUNT = readUint256("MIN_STAKE_AMOUNT");
        uint256 MAX_UNSTAKE_REQUESTS = readUint256("MAX_UNSTAKE_REQUESTS");
        uint256 UNSTAKE_PERIOD = readUint256("UNSTAKE_PERIOD");
        uint256 SLASH_CANCELLATION_PERIOD = readUint256("SLASH_CANCELLATION_PERIOD");

        // Encode the initialize function call data
        bytes memory initData = abi.encodeCall(
            SuccinctStaking.initialize,
            (
                OWNER,
                GOVERNOR,
                VAPP,
                PROVE,
                I_PROVE,
                DISPENSER,
                MIN_STAKE_AMOUNT,
                MAX_UNSTAKE_REQUESTS,
                UNSTAKE_PERIOD,
                SLASH_CANCELLATION_PERIOD
            )
        );

        // Deploy contract
        address STAKING_IMPL = address(new SuccinctStaking{salt: salt}());
        address STAKING = address(
            SuccinctStaking(payable(address(new ERC1967Proxy{salt: salt}(STAKING_IMPL, initData))))
        );

        // Write address
        writeAddress(KEY, STAKING);
        writeAddress(string.concat(KEY, "_IMPL"), STAKING_IMPL);
    }
}
