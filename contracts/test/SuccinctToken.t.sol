// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Succinct} from "../src/tokens/Succinct.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract SuccinctTokenTest is Test {
    address public OWNER;
    Succinct public PROVE;

    function setUp() public {
        OWNER = makeAddr("OWNER");
        PROVE = new Succinct(OWNER);
    }

    function test_InitialOwner() public view {
        assertEq(PROVE.owner(), OWNER);
    }

    function test_Mint_WhenOwner() public {
        vm.startPrank(OWNER);
        PROVE.mint(OWNER, 100);
        assertEq(PROVE.balanceOf(OWNER), 100);
    }

    function test_RevertMint_WhenNotOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this))
        );
        PROVE.mint(address(this), 100);
    }
}
