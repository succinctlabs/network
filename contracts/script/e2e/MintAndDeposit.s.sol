// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {MockUSDC} from "../../src/mocks/MockUSDC.sol";
import {MockVApp} from "../../src/mocks/MockVApp.sol";

contract MintAndDepositScript is BaseScript {
    // Mint USDC and deposit it into VAPP.
    function run() external broadcaster {
        // Read config
        address USDC = readAddress("USDC");
        address VAPP = readAddress("VAPP");

        // Mint USDC
        MockUSDC(USDC).mint(msg.sender, 10e18);

        // Deposit USDC into VAPP
        MockUSDC(USDC).approve(VAPP, 10e18);
        MockVApp(VAPP).deposit(10e18);
    }
}
