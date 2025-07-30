// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {StepPublicValues, Receipt as TxReceipt} from "../src/libraries/PublicValues.sol";

contract SuccinctVAppForkTest is SuccinctVAppTest {
    function test_Fork_WhenValid() public {
        bytes32 oldVkey = SuccinctVApp(VAPP).vkey();
        bytes32 newVkey = bytes32(uint256(1));
        bytes32 newRoot = bytes32(uint256(2));

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Fork(1, oldVkey, newVkey);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, fixture.oldRoot, newRoot);

        vm.prank(OWNER);
        (uint64 newblock, bytes32 returnedOldRoot, bytes32 returnedNewRoot) =
            SuccinctVApp(VAPP).fork(newVkey, newRoot);

        assertEq(SuccinctVApp(VAPP).vkey(), newVkey);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(1), newRoot);
        assertEq(newblock, 1);
        assertEq(returnedNewRoot, newRoot);
        assertEq(returnedOldRoot, fixture.oldRoot);
    }

    function test_Fork_WhenValidAfterUpdateState() public {
        // Update state
        mockCall(true);

        StepPublicValues memory publicValues1 = StepPublicValues({
            receipts: new TxReceipt[](0),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });

        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues1), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(1), bytes32(uint256(1)));
        assertEq(SuccinctVApp(VAPP).vkey(), jsonFixture.vkey);

        // Fork
        bytes32 oldVkey = SuccinctVApp(VAPP).vkey();
        bytes32 oldRoot = SuccinctVApp(VAPP).roots(1);
        bytes32 newVkey = bytes32(uint256(99));
        bytes32 newRoot = bytes32(uint256(2));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Fork(2, oldVkey, newVkey);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, oldRoot, newRoot);

        vm.prank(OWNER);
        (uint64 newBlock, bytes32 returnedOldRoot, bytes32 returnedNewRoot) =
            SuccinctVApp(VAPP).fork(newVkey, newRoot);

        assertEq(SuccinctVApp(VAPP).vkey(), newVkey);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 2);
        assertEq(SuccinctVApp(VAPP).roots(1), bytes32(uint256(1)));
        assertEq(SuccinctVApp(VAPP).roots(2), newRoot);
        assertEq(newBlock, 2);
        assertEq(returnedNewRoot, newRoot);
        assertEq(returnedOldRoot, bytes32(uint256(1)));
    }
}
