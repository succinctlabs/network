// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Receipt as TxReceipt, StepPublicValues} from "../src/libraries/PublicValues.sol";

contract SuccinctVAppStateTest is SuccinctVAppTest {
    function test_Step_WhenValid() public {
        mockCall(true);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 0);
        assertEq(SuccinctVApp(VAPP).roots(0), fixture.oldRoot);
        assertEq(SuccinctVApp(VAPP).roots(1), bytes32(0));
        assertEq(SuccinctVApp(VAPP).root(), fixture.oldRoot);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, fixture.oldRoot, fixture.newRoot);
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(0), fixture.oldRoot);
        assertEq(SuccinctVApp(VAPP).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(VAPP).root(), fixture.newRoot);
    }

    function test_Step_WhenValidTwice() public {
        mockCall(true);

        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(0), fixture.oldRoot);
        assertEq(SuccinctVApp(VAPP).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(VAPP).roots(2), bytes32(0));
        assertEq(SuccinctVApp(VAPP).root(), fixture.newRoot);

        StepPublicValues memory publicValues = StepPublicValues({
            receipts: new TxReceipt[](0),
            oldRoot: fixture.newRoot,
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, publicValues.oldRoot, publicValues.newRoot);
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 2);
        assertEq(SuccinctVApp(VAPP).roots(0), fixture.oldRoot);
        assertEq(SuccinctVApp(VAPP).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(VAPP).roots(2), publicValues.newRoot);
        assertEq(SuccinctVApp(VAPP).root(), publicValues.newRoot);
    }

    function test_RevertStep_WhenInvalid() public {
        bytes memory fakeProof = new bytes(jsonFixture.proof.length);

        mockCall(false);
        vm.expectRevert();
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(jsonFixture.publicValues, fakeProof);
    }

    function test_RevertStep_WhenInvalidRoot() public {
        StepPublicValues memory publicValues = StepPublicValues({
            receipts: new TxReceipt[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(0),
            timestamp: uint64(block.timestamp)
        });

        mockCall(true);
        vm.expectRevert(ISuccinctVApp.InvalidRoot.selector);
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertStep_WhenInvalidOldRoot() public {
        mockCall(true);
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(jsonFixture.publicValues, jsonFixture.proof);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).root(), fixture.newRoot);

        StepPublicValues memory publicValues = StepPublicValues({
            receipts: new TxReceipt[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectRevert(ISuccinctVApp.InvalidOldRoot.selector);
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertStep_WhenInvalidTimestampFuture() public {
        mockCall(true);

        // Create public values with a future timestamp
        StepPublicValues memory publicValues = StepPublicValues({
            receipts: new TxReceipt[](0),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp + 1 days) // Timestamp in the future
        });

        vm.expectRevert(ISuccinctVApp.InvalidTimestamp.selector);
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertStep_WhenTimestampInPast() public {
        mockCall(true);

        // First update with current timestamp
        uint64 initialTime = uint64(block.timestamp);
        StepPublicValues memory initialPublicValues = StepPublicValues({
            receipts: new TxReceipt[](0),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: initialTime
        });

        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(initialPublicValues), jsonFixture.proof);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);

        // Capture the timestamp that was recorded
        uint64 recordedTimestamp = SuccinctVApp(VAPP).timestamps(1);

        // Create public values with a timestamp earlier than the previous block
        StepPublicValues memory publicValues = StepPublicValues({
            receipts: new TxReceipt[](0),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: recordedTimestamp - 1 // Timestamp earlier than previous block
        });

        vm.expectRevert(ISuccinctVApp.TimestampInPast.selector);
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertStep_WhenTimestampTooOld() public {
        mockCall(true);

        // Warp to a time where we can safely subtract 1 hour.
        vm.warp(2 hours);

        // Create public values with a timestamp more than 1 hour in the past.
        StepPublicValues memory publicValues = StepPublicValues({
            receipts: new TxReceipt[](0),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp - 1 hours - 1) // More than 1 hour in the past
        });

        vm.expectRevert(ISuccinctVApp.TimestampTooOld.selector);
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_Step_WhenTimestampExactlyOneHourOld() public {
        mockCall(true);

        // Warp to a time where we can safely subtract 1 hour.
        vm.warp(2 hours);

        // Create public values with a timestamp exactly 1 hour in the past.
        StepPublicValues memory publicValues = StepPublicValues({
            receipts: new TxReceipt[](0),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp - 1 hours) // Exactly 1 hour in the past
        });

        // This should succeed as it's exactly at the boundary.
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, fixture.oldRoot, publicValues.newRoot);
        vm.prank(AUCTIONEER);
        SuccinctVApp(VAPP).step(abi.encode(publicValues), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(1), publicValues.newRoot);
        assertEq(SuccinctVApp(VAPP).root(), publicValues.newRoot);
    }

    function test_RevertStep_WhenNotAuctioneer() public {
        vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.NotAuctioneer.selector));
        vm.prank(REQUESTER_1);
        SuccinctVApp(VAPP).step(jsonFixture.publicValues, jsonFixture.proof);
    }
}
