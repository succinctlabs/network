// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {SuccinctVApp} from "../../src/SuccinctVApp.sol";
import {ERC1967Proxy} from
    "../../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SuccinctVAppScript is BaseScript {
    string internal constant KEY = "VAPP";

    function run() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address OWNER = readAddress("OWNER");
        address PROVE = readAddress("PROVE");
        address I_PROVE = readAddress("I_PROVE");
        address AUCTIONEER = readAddress("AUCTIONEER");
        address STAKING = readAddress("STAKING");
        address VERIFIER = readAddress("VERIFIER");
        uint256 MIN_DEPOSIT_AMOUNT = readUint256("MIN_DEPOSIT_AMOUNT");
        bytes32 VKEY = readBytes32("VKEY");
        bytes32 GENESIS_STATE_ROOT = readBytes32("GENESIS_STATE_ROOT");

        // Encode the initialize function call data
        bytes memory initData = abi.encodeCall(
            SuccinctVApp.initialize,
            (
                OWNER,
                PROVE,
                I_PROVE,
                AUCTIONEER,
                STAKING,
                VERIFIER,
                MIN_DEPOSIT_AMOUNT,
                VKEY,
                GENESIS_STATE_ROOT
            )
        );

        // Deploy contract
        address VAPP_IMPL = address(new SuccinctVApp{salt: salt}());
        address VAPP = address(
            SuccinctVApp(payable(address(new ERC1967Proxy{salt: salt}(VAPP_IMPL, initData))))
        );

        // Write address
        writeAddress(KEY, VAPP);
        writeAddress(string.concat(KEY, "_IMPL"), VAPP_IMPL);
    }

    function upgrade() external broadcaster {
        // Read config
        bytes32 salt = readBytes32("CREATE2_SALT");
        address PROXY = readAddress(KEY);

        // Deploy contract
        address VAPP_IMPL = address(new SuccinctVApp{salt: salt}());
        SuccinctVApp(payable(PROXY)).upgradeToAndCall(VAPP_IMPL, "");

        // Proxy adress is still the same, only update the implementation
        writeAddress(string.concat(KEY, "_IMPL"), VAPP_IMPL);
    }
}
