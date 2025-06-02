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
    ProverAction
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {MockStaking} from "../src/mocks/MockStaking.sol";

contract SuccinctVAppDelegateTest is SuccinctVAppTest {
    function test_Prover_WhenProverCreated() public {
		// Create the prover, this emits a Prover action for the prover owner being
		// a delegate of the prover.
		vm.expectEmit(true, true, true, false);
        emit ISuccinctVApp.ReceiptPending(1, ActionType.Prover, bytes(""));
        vm.prank(ALICE);
        address aliceProver = MockStaking(STAKING).createProver(ALICE, STAKER_FEE_BIPS);

		// The expected action data for alice creating a prover.
        bytes memory expectedProverData =
            abi.encode(ProverAction({prover: aliceProver, owner: ALICE, stakerFeeBips: STAKER_FEE_BIPS}));

        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(VAPP).receipts(SuccinctVApp(VAPP).currentReceipt());
        assertEq(uint8(actionType), uint8(ActionType.Prover));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, expectedProverData);

        // Process the first setDelegatedSigner action through state update
        PublicValuesStruct memory publicValues1 = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues1.actions[0] = Action({
            action: ActionType.Prover,
            status: ReceiptStatus.Completed,
            receipt: SuccinctVApp(VAPP).currentReceipt(),
            data: expectedProverData
        });

        mockCall(true);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues1.newRoot, publicValues1.oldRoot);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues1), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).receipts(SuccinctVApp(VAPP).currentReceipt());
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 1);
    }
}
