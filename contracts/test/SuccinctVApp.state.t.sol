// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Actions} from "../src/libraries/Actions.sol";
import {
    PublicValuesStruct,
    ReceiptStatus,
    Action,
    ActionType,
    DepositAction,
    WithdrawAction,
    AddSignerAction,
    RemoveSignerAction
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";

contract SuccinctVAppStateTest is SuccinctVAppTest {
    function test_UpdateState_WhenValid() public {
        mockCall(true);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 0);
        assertEq(SuccinctVApp(VAPP).roots(0), bytes32(0));
        assertEq(SuccinctVApp(VAPP).roots(1), bytes32(0));
        assertEq(SuccinctVApp(VAPP).root(), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, fixture.newRoot, fixture.oldRoot);
        SuccinctVApp(VAPP).updateState(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(0), bytes32(0));
        assertEq(SuccinctVApp(VAPP).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(VAPP).root(), fixture.newRoot);
    }

    function test_UpdateState_WhenValidTwice() public {
        mockCall(true);

        SuccinctVApp(VAPP).updateState(jsonFixture.publicValues, jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(0), bytes32(0));
        assertEq(SuccinctVApp(VAPP).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(VAPP).roots(2), bytes32(0));
        assertEq(SuccinctVApp(VAPP).root(), fixture.newRoot);

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: fixture.newRoot,
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, publicValues.newRoot, publicValues.oldRoot);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 2);
        assertEq(SuccinctVApp(VAPP).roots(0), bytes32(0));
        assertEq(SuccinctVApp(VAPP).roots(1), fixture.newRoot);
        assertEq(SuccinctVApp(VAPP).roots(2), publicValues.newRoot);
        assertEq(SuccinctVApp(VAPP).root(), publicValues.newRoot);
    }

    function test_RevertUpdateState_WhenInvalid() public {
        bytes memory fakeProof = new bytes(jsonFixture.proof.length);

        mockCall(false);
        vm.expectRevert();
        SuccinctVApp(VAPP).updateState(jsonFixture.publicValues, fakeProof);
    }

    function test_RevertUpdateState_WhenInvalidRoot() public {
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(0),
            timestamp: uint64(block.timestamp)
        });

        mockCall(true);
        vm.expectRevert(ISuccinctVApp.InvalidRoot.selector);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertUpdateState_WhenInvalidOldRoot() public {
        mockCall(true);
        SuccinctVApp(VAPP).updateState(jsonFixture.publicValues, jsonFixture.proof);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).root(), fixture.newRoot);

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(uint256(999)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });

        vm.expectRevert(ISuccinctVApp.InvalidOldRoot.selector);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertUpdateState_WhenInvalidTimestampFuture() public {
        mockCall(true);

        // Create public values with a future timestamp
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp + 1 days) // Timestamp in the future
        });

        vm.expectRevert(ISuccinctVApp.InvalidTimestamp.selector);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
    }

    function test_RevertUpdateState_WhenTimestampInPast() public {
        mockCall(true);

        // First update with current timestamp
        uint64 initialTime = uint64(block.timestamp);
        PublicValuesStruct memory initialPublicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: initialTime
        });

        SuccinctVApp(VAPP).updateState(abi.encode(initialPublicValues), jsonFixture.proof);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);

        // Capture the timestamp that was recorded
        uint64 recordedTimestamp = SuccinctVApp(VAPP).timestamps(1);

        // Create public values with a timestamp earlier than the previous block
        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: recordedTimestamp - 1 // Timestamp earlier than previous block
        });

        vm.expectRevert(ISuccinctVApp.TimestampInPast.selector);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues), jsonFixture.proof);
    }
}
