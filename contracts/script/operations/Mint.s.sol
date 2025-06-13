// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BaseScript} from "../utils/Base.s.sol";
import {Succinct} from "../../src/tokens/Succinct.sol";

contract MintScript is BaseScript {
    function run() external broadcaster {
        // Read config
        address PROVE = readAddress("PROVE");
        uint256 MINT_AMOUNT = 1_000_000_000e18; // 1 billion $PROVE

        // Mint $PROVE tokens
        Succinct(PROVE).mint(msg.sender, MINT_AMOUNT);
    }
}
