// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {MockVApp} from "../src/mocks/MockVApp.sol";

contract DebugTest is Test {
    MockVApp public vapp;
    address public prover = address(0x123);

    function setUp() public {
        vapp = new MockVApp();
    }

    function test_RequestWithdrawWithZeroBalance() public {
        // Check initial balance
        assertEq(vapp.balances(prover), 0);
        
        // This should not revert
        vapp.requestWithdraw(prover, type(uint256).max);
        
        // Check final state
        assertEq(vapp.balances(prover), 0);
        assertEq(vapp.withdrawClaims(prover), 0);
    }
} 