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
    SetDelegatedSignerAction,
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";

contract SuccinctVAppForkTest is SuccinctVAppTest {
    function test_Fork_WhenValid() public {
        bytes32 newVkey = bytes32(uint256(1));
        bytes32 newRoot = bytes32(uint256(2));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: newRoot,
            timestamp: uint64(block.timestamp)
        });

        mockCall(true);

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, newRoot, bytes32(0));
        emit ISuccinctVApp.Fork(newVkey, 1, newRoot, bytes32(0));

        (uint64 _block, bytes32 returnedNewRoot, bytes32 returnedOldRoot) =
            SuccinctVApp(VAPP).fork(newVkey, newRoot, abi.encode(publicValues), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).vappProgramVKey(), newVkey);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(1), newRoot);
        assertEq(_block, 1);
        assertEq(returnedNewRoot, newRoot);
        assertEq(returnedOldRoot, bytes32(0));
    }

    function test_Fork_WhenValidAfterUpdateState() public {
        // Update state
        mockCall(true);

        PublicValuesStruct memory publicValues1 = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });

        SuccinctVApp(VAPP).updateState(abi.encode(publicValues1), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(SuccinctVApp(VAPP).roots(1), bytes32(uint256(1)));
        assertEq(SuccinctVApp(VAPP).vappProgramVKey(), jsonFixture.vkey);

        // Fork
        bytes32 newVkey = bytes32(uint256(99));
        bytes32 newRoot = bytes32(uint256(2));

        PublicValuesStruct memory publicValues2 = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(uint256(1)),
            newRoot: newRoot,
            timestamp: uint64(block.timestamp)
        });

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, newRoot, bytes32(uint256(1)));
        emit ISuccinctVApp.Fork(newVkey, 2, newRoot, bytes32(uint256(1)));

        (uint64 blockNum, bytes32 returnedNewRoot, bytes32 returnedOldRoot) =
            SuccinctVApp(VAPP).fork(newVkey, newRoot, abi.encode(publicValues2), jsonFixture.proof);

        assertEq(SuccinctVApp(VAPP).vappProgramVKey(), newVkey);
        assertEq(SuccinctVApp(VAPP).blockNumber(), 2);
        assertEq(SuccinctVApp(VAPP).roots(1), bytes32(uint256(1)));
        assertEq(SuccinctVApp(VAPP).roots(2), newRoot);
        assertEq(blockNum, 2);
        assertEq(returnedNewRoot, newRoot);
        assertEq(returnedOldRoot, bytes32(uint256(1)));
    }

    function test_RevertFork_WhenUnauthorized() public {
        bytes32 newVkey = bytes32(uint256(1));
        bytes32 newRoot = bytes32(uint256(2));

        PublicValuesStruct memory publicValues = PublicValuesStruct({
            actions: new Action[](0),
            oldRoot: bytes32(0),
            newRoot: newRoot,
            timestamp: uint64(block.timestamp)
        });

        vm.prank(REQUESTER_1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", REQUESTER_1));
        SuccinctVApp(VAPP).fork(newVkey, newRoot, abi.encode(publicValues), jsonFixture.proof);
    }
}
