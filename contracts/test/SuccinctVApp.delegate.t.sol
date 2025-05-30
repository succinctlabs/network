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
    SetDelegatedSignerAction
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {MockStaking} from "../src/mocks/MockStaking.sol";

contract SuccinctVAppDelegateTest is SuccinctVAppTest {
    function test_SetDelegatedSigner_WhenProverCreated() public {
		// Create the prover, this emits a SetDelegatedSigner action for the prover owner being
		// a delegate of the prover.
		vm.expectEmit(true, true, true, false);
        emit ISuccinctVApp.ReceiptPending(1, ActionType.SetDelegatedSigner, bytes(""));
        vm.prank(ALICE);
        address aliceProver = MockStaking(STAKING).createProver(STAKER_FEE_BIPS);

		// The expected action data for alice creating a prover.
        bytes memory expectedSetDelegatedSignerData =
            abi.encode(SetDelegatedSignerAction({owner: aliceProver, signer: ALICE}));

        (ActionType actionType, ReceiptStatus status,, bytes memory data) =
            SuccinctVApp(VAPP).receipts(SuccinctVApp(VAPP).currentReceipt());
        assertEq(uint8(actionType), uint8(ActionType.SetDelegatedSigner));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));
        assertEq(data, expectedSetDelegatedSignerData);

        // Process the first setDelegatedSigner action through state update
        PublicValuesStruct memory publicValues1 = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues1.actions[0] = Action({
            action: ActionType.SetDelegatedSigner,
            status: ReceiptStatus.Completed,
            receipt: SuccinctVApp(VAPP).currentReceipt(),
            data: expectedSetDelegatedSignerData
        });

        mockCall(true);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues1.newRoot, publicValues1.oldRoot);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues1), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).receipts(SuccinctVApp(VAPP).currentReceipt());
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 1);

        // Verify delegated signer was added
        address signer = SuccinctVApp(VAPP).delegatedSigner(aliceProver);
        assertEq(signer, ALICE);
        assertTrue(SuccinctVApp(VAPP).usedSigners(ALICE));
    }

	function test_SetDelegatedSigner_WhenNewSignerIsSet() public {
		// Create the prover, this emits a SetDelegatedSigner action for the prover owner being
		// a delegate of the prover.
        vm.prank(ALICE);
        address aliceProver = MockStaking(STAKING).createProver(STAKER_FEE_BIPS);

		// The expected action data for alice creating a prover.
        bytes memory expectedSetDelegatedSignerData =
            abi.encode(SetDelegatedSignerAction({owner: aliceProver, signer: ALICE}));

        // Process the first setDelegatedSigner action through state update
        PublicValuesStruct memory publicValues1 = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(0),
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues1.actions[0] = Action({
            action: ActionType.SetDelegatedSigner,
            status: ReceiptStatus.Completed,
            receipt: SuccinctVApp(VAPP).currentReceipt(),
            data: expectedSetDelegatedSignerData
        });
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues1), jsonFixture.proof);

        // Add a new delegated signer for the prover
        bytes memory expectedSetDelegatedSignerData2 =
            abi.encode(SetDelegatedSignerAction({owner: aliceProver, signer: BOB}));

        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.ReceiptPending(2, ActionType.SetDelegatedSigner, expectedSetDelegatedSignerData2);
		vm.prank(ALICE);
        uint64 setDelegatedSignerReceipt2 = MockStaking(STAKING).setDelegatedSigner(aliceProver, BOB);

        assertEq(setDelegatedSignerReceipt2, 2);
        (ActionType actionType, ReceiptStatus status,,) = SuccinctVApp(VAPP).receipts(setDelegatedSignerReceipt2);
        assertEq(uint8(actionType), uint8(ActionType.SetDelegatedSigner));
        assertEq(uint8(status), uint8(ReceiptStatus.Pending));

        // Process the second setDelegatedSigner action through state update
        PublicValuesStruct memory publicValues2 = PublicValuesStruct({
            actions: new Action[](1),
            oldRoot: bytes32(uint256(1)),
            newRoot: bytes32(uint256(2)),
            timestamp: uint64(block.timestamp)
        });
        publicValues2.actions[0] = Action({
            action: ActionType.SetDelegatedSigner,
            status: ReceiptStatus.Completed,
            receipt: setDelegatedSignerReceipt2,
            data: expectedSetDelegatedSignerData2
        });

        mockCall(true);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(2, publicValues2.newRoot, publicValues2.oldRoot);
        SuccinctVApp(VAPP).updateState(abi.encode(publicValues2), jsonFixture.proof);

        // Verify second receipt status updated
        (, status,,) = SuccinctVApp(VAPP).receipts(setDelegatedSignerReceipt2);
        assertEq(uint8(status), uint8(ReceiptStatus.Completed));

        // Verify finalizedReceipt updated
        assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 2);

        // Verify delegated signer was updated
        address signer = SuccinctVApp(VAPP).delegatedSigner(aliceProver);
        assertEq(signer, BOB);
        assertTrue(SuccinctVApp(VAPP).usedSigners(BOB));
    }

    // function test_AddDelegatedSigner_WhenValid() public {
	// 	// Create the prover, this emits a SetDelegatedSigner action for the prover owner being
	// 	// a delegate of the prover.
	// 	vm.expectEmit(true, true, true, true);
    //     emit ISuccinctVApp.ReceiptPending(1, ActionType.SetDelegatedSigner, setDelegatedSignerData1);
    //     vm.prank(ALICE);
    //     address aliceProver = MockStaking(STAKING).createProver(STAKER_FEE_BIPS);

    //     // Add first delegated signer
    //     bytes memory setDelegatedSignerData1 =
    //         abi.encode(SetDelegatedSignerAction({owner: aliceProver, signer: ALICE}));

    //     uint64 setDelegatedSignerReceipt1 = SuccinctVApp(VAPP).addDelegatedSigner(ALICE, ALICE);

    //     assertEq(setDelegatedSignerReceipt1, 1);
    //     (ActionType actionType, ReceiptStatus status,, bytes memory data) =
    //         SuccinctVApp(VAPP).receipts(setDelegatedSignerReceipt1);
    //     assertEq(uint8(actionType), uint8(ActionType.SetDelegatedSigner));
    //     assertEq(uint8(status), uint8(ReceiptStatus.Pending));
    //     assertEq(data, setDelegatedSignerData1);

    //     // Process the first setDelegatedSigner action through state update
    //     PublicValuesStruct memory publicValues1 = PublicValuesStruct({
    //         actions: new Action[](1),
    //         oldRoot: bytes32(0),
    //         newRoot: bytes32(uint256(1)),
    //         timestamp: uint64(block.timestamp)
    //     });
    //     publicValues1.actions[0] = Action({
    //         action: ActionType.SetDelegatedSigner,
    //         status: ReceiptStatus.Completed,
    //         receipt: setDelegatedSignerReceipt1,
    //         data: setDelegatedSignerData1
    //     });

    //     mockCall(true);
    //     vm.expectEmit(true, true, true, true);
    //     emit ISuccinctVApp.Block(1, publicValues1.newRoot, publicValues1.oldRoot);
    //     SuccinctVApp(VAPP).updateState(abi.encode(publicValues1), jsonFixture.proof);

    //     // Verify receipt status updated
    //     (, status,,) = SuccinctVApp(VAPP).receipts(setDelegatedSignerReceipt1);
    //     assertEq(uint8(status), uint8(ReceiptStatus.Completed));
    //     assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 1);

    //     // Verify first delegated signer was added
    //     address[] memory signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
    //     assertEq(signers.length, 1);
    //     assertEq(signers[0], signer1);
    //     assertTrue(SuccinctVApp(VAPP).usedSigners(signer1));

    //     // Add second delegated signer
    //     vm.startPrank(REQUESTER_1);
    //     bytes memory setDelegatedSignerData2 =
    //         abi.encode(SetDelegatedSignerAction({owner: REQUESTER_1, signer: signer2}));

    //     vm.expectEmit(true, true, true, true);
    //     emit ISuccinctVApp.ReceiptPending(2, ActionType.SetDelegatedSigner, setDelegatedSignerData2);
    //     uint64 setDelegatedSignerReceipt2 = SuccinctVApp(VAPP).addDelegatedSigner(signer2);
    //     vm.stopPrank();

    //     assertEq(setDelegatedSignerReceipt2, 2);
    //     (actionType, status,,) = SuccinctVApp(VAPP).receipts(setDelegatedSignerReceipt2);
    //     assertEq(uint8(actionType), uint8(ActionType.SetDelegatedSigner));
    //     assertEq(uint8(status), uint8(ReceiptStatus.Pending));

    //     // Process the second setDelegatedSigner action through state update
    //     PublicValuesStruct memory publicValues2 = PublicValuesStruct({
    //         actions: new Action[](1),
    //         oldRoot: bytes32(uint256(1)),
    //         newRoot: bytes32(uint256(2)),
    //         timestamp: uint64(block.timestamp)
    //     });
    //     publicValues2.actions[0] = Action({
    //         action: ActionType.SetDelegatedSigner,
    //         status: ReceiptStatus.Completed,
    //         receipt: setDelegatedSignerReceipt2,
    //         data: setDelegatedSignerData2
    //     });

    //     mockCall(true);
    //     vm.expectEmit(true, true, true, true);
    //     emit ISuccinctVApp.Block(2, publicValues2.newRoot, publicValues2.oldRoot);
    //     SuccinctVApp(VAPP).updateState(abi.encode(publicValues2), jsonFixture.proof);

    //     // Verify second receipt status updated
    //     (, status,,) = SuccinctVApp(VAPP).receipts(setDelegatedSignerReceipt2);
    //     assertEq(uint8(status), uint8(ReceiptStatus.Completed));

    //     // Verify finalizedReceipt updated
    //     assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 2);

    //     // Verify both delegated signers are in the array
    //     signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
    //     assertEq(signers.length, 2);
    //     assertEq(signers[0], signer1);
    //     assertEq(signers[1], signer2);
    //     assertTrue(SuccinctVApp(VAPP).usedSigners(signer1));
    //     assertTrue(SuccinctVApp(VAPP).usedSigners(signer2));
    // }

//     function test_RevertAddDelegatedSigner_WhenNotProverOwner() public {
//         // user1 is not a prover owner
//         address signer = makeAddr("signer");

//         vm.startPrank(REQUESTER_1);
//         vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.InvalidSigner.selector));
//         SuccinctVApp(VAPP).addDelegatedSigner(signer);
//         vm.stopPrank();

//         // Verify no receipt was created
//         assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
//     }

//     function test_RevertAddDelegatedSigner_WhenZeroAddress() public {
//         // Setup user1 as a prover owner
//         MockStaking(STAKING).setHasProver(REQUESTER_1, true);

//         vm.startPrank(REQUESTER_1);
//         vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.ZeroAddress.selector));
//         SuccinctVApp(VAPP).addDelegatedSigner(address(0));
//         vm.stopPrank();

//         // Verify no receipt was created
//         assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
//     }

//     function test_RevertAddDelegatedSigner_WhenProver() public {
//         // Setup user1 as a prover owner and user2 as a prover
//         MockStaking(STAKING).setHasProver(REQUESTER_1, true);
//         MockStaking(STAKING).setIsProver(REQUESTER_2, true);

//         vm.startPrank(REQUESTER_1);
//         vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.InvalidSigner.selector));
//         SuccinctVApp(VAPP).addDelegatedSigner(REQUESTER_2);
//         vm.stopPrank();

//         // Verify no receipt was created
//         assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
//     }

//     function test_RevertAddDelegatedSigner_WhenHasProver() public {
//         // Setup user1 and user2 as prover owners
//         MockStaking(STAKING).setHasProver(REQUESTER_1, true);
//         MockStaking(STAKING).setHasProver(REQUESTER_2, true);

//         vm.startPrank(REQUESTER_1);
//         vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.InvalidSigner.selector));
//         SuccinctVApp(VAPP).addDelegatedSigner(REQUESTER_2);
//         vm.stopPrank();

//         // Verify no receipt was created
//         assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
//     }

//     function test_RevertAddDelegatedSigner_WhenAlreadyUsed() public {
//         // Setup user1 and user2 as prover owners
//         MockStaking(STAKING).setHasProver(REQUESTER_1, true);
//         MockStaking(STAKING).setHasProver(REQUESTER_2, true);

//         address signer = makeAddr("signer");

//         // Add signer to user1
//         vm.startPrank(REQUESTER_1);
//         SuccinctVApp(VAPP).addDelegatedSigner(signer);
//         vm.stopPrank();

//         // Try to add the same signer to user2
//         vm.startPrank(REQUESTER_2);
//         vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.InvalidSigner.selector));
//         SuccinctVApp(VAPP).addDelegatedSigner(signer);
//         vm.stopPrank();

//         // Verify only one receipt was created
//         assertEq(SuccinctVApp(VAPP).currentReceipt(), 1);
//     }

//     function test_RemoveDelegatedSigner_WhenValid() public {
//         // Setup user1 as a prover owner and add two delegated signers (one at a time to avoid stack issues)
//         MockStaking(STAKING).setHasProver(REQUESTER_1, true);
//         address signer1 = makeAddr("signer1");
//         address signer2 = makeAddr("signer2");

//         // Add signers one by one to avoid stack too deep issues
//         vm.startPrank(REQUESTER_1);
//         uint64 setDelegatedSignerReceipt1 = SuccinctVApp(VAPP).addDelegatedSigner(signer1);
//         vm.stopPrank();

//         // Process the first setDelegatedSigner action
//         bytes memory setDelegatedSignerData1 =
//             abi.encode(SetDelegatedSignerAction({owner: REQUESTER_1, signer: signer1}));
//         PublicValuesStruct memory addPublicValues1 = PublicValuesStruct({
//             actions: new Action[](1),
//             oldRoot: bytes32(0),
//             newRoot: bytes32(uint256(1)),
//             timestamp: uint64(block.timestamp)
//         });
//         addPublicValues1.actions[0] = Action({
//             action: ActionType.SetDelegatedSigner,
//             status: ReceiptStatus.Completed,
//             receipt: setDelegatedSignerReceipt1,
//             data: setDelegatedSignerData1
//         });

//         mockCall(true);
//         SuccinctVApp(VAPP).updateState(abi.encode(addPublicValues1), jsonFixture.proof);

//         // Add second signer
//         vm.startPrank(REQUESTER_1);
//         uint64 setDelegatedSignerReceipt2 = SuccinctVApp(VAPP).addDelegatedSigner(signer2);
//         vm.stopPrank();

//         // Process the second setDelegatedSigner action
//         bytes memory setDelegatedSignerData2 =
//             abi.encode(SetDelegatedSignerAction({owner: REQUESTER_1, signer: signer2}));
//         PublicValuesStruct memory addPublicValues2 = PublicValuesStruct({
//             actions: new Action[](1),
//             oldRoot: bytes32(uint256(1)),
//             newRoot: bytes32(uint256(2)),
//             timestamp: uint64(block.timestamp)
//         });
//         addPublicValues2.actions[0] = Action({
//             action: ActionType.SetDelegatedSigner,
//             status: ReceiptStatus.Completed,
//             receipt: setDelegatedSignerReceipt2,
//             data: setDelegatedSignerData2
//         });

//         mockCall(true);
//         SuccinctVApp(VAPP).updateState(abi.encode(addPublicValues2), jsonFixture.proof);

//         // Verify both signers were added
//         address[] memory signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
//         assertEq(signers.length, 2);
//         assertEq(signers[0], signer1);
//         assertEq(signers[1], signer2);
//         assertTrue(SuccinctVApp(VAPP).usedSigners(signer1));
//         assertTrue(SuccinctVApp(VAPP).usedSigners(signer2));
//         assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 2);

//         // Now, remove the first delegated signer
//         vm.startPrank(REQUESTER_1);
//         bytes memory removeSignerData =
//             abi.encode(RemoveSignerAction({owner: REQUESTER_1, signer: signer1}));

//         vm.expectEmit(true, true, true, true);
//         emit ISuccinctVApp.ReceiptPending(3, ActionType.RemoveSigner, removeSignerData);
//         uint64 removeSignerReceipt = SuccinctVApp(VAPP).removeDelegatedSigner(signer1);
//         vm.stopPrank();

//         // Check receipt details
//         (ActionType actionType, ReceiptStatus status,,) =
//             SuccinctVApp(VAPP).receipts(removeSignerReceipt);
//         assertEq(uint8(actionType), uint8(ActionType.RemoveSigner));
//         assertEq(uint8(status), uint8(ReceiptStatus.Pending));

//         // Verify first signer was removed after the removal operation
//         signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
//         assertEq(signers.length, 1);
//         assertEq(signers[0], signer2); // signer2 should remain

//         // Check usage flags
//         bool isSigner1Used = SuccinctVApp(VAPP).usedSigners(signer1);
//         bool isSigner2Used = SuccinctVApp(VAPP).usedSigners(signer2);
//         assertFalse(isSigner1Used);
//         assertTrue(isSigner2Used);

//         // Process the removeSigner action through state update
//         PublicValuesStruct memory removePublicValues = PublicValuesStruct({
//             actions: new Action[](1),
//             oldRoot: bytes32(uint256(2)),
//             newRoot: bytes32(uint256(3)),
//             timestamp: uint64(block.timestamp)
//         });
//         removePublicValues.actions[0] = Action({
//             action: ActionType.RemoveSigner,
//             status: ReceiptStatus.Completed,
//             receipt: removeSignerReceipt,
//             data: removeSignerData
//         });

//         mockCall(true);
//         vm.expectEmit(true, true, true, true);
//         emit ISuccinctVApp.Block(3, removePublicValues.newRoot, removePublicValues.oldRoot);
//         SuccinctVApp(VAPP).updateState(abi.encode(removePublicValues), jsonFixture.proof);

//         // Verify receipt status updated
//         (, status,,) = SuccinctVApp(VAPP).receipts(removeSignerReceipt);
//         assertEq(uint8(status), uint8(ReceiptStatus.Completed));

//         // Verify finalizedReceipt updated
//         assertEq(SuccinctVApp(VAPP).finalizedReceipt(), 3);
//     }

//     function test_RevertRemoveDelegatedSigner_WhenNotOwner() public {
//         // Setup user1 as a prover owner and add a delegated signer
//         MockStaking(STAKING).setHasProver(REQUESTER_1, true);
//         MockStaking(STAKING).setHasProver(REQUESTER_2, true);
//         address signer = makeAddr("signer");

//         vm.prank(REQUESTER_1);
//         SuccinctVApp(VAPP).addDelegatedSigner(signer);

//         // User2 tries to remove user1's signer
//         vm.startPrank(REQUESTER_2);
//         vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.InvalidSigner.selector));
//         SuccinctVApp(VAPP).removeDelegatedSigner(signer);
//         vm.stopPrank();

//         // Verify signer is still in user1's delegated signers
//         address[] memory signers = SuccinctVApp(VAPP).getDelegatedSigners(REQUESTER_1);
//         assertEq(signers.length, 1);
//         assertEq(signers[0], signer);
//         assertTrue(SuccinctVApp(VAPP).usedSigners(signer));
//     }

//     function test_RevertRemoveDelegatedSigner_WhenNotRegistered() public {
//         // Setup user1 as a prover owner
//         MockStaking(STAKING).setHasProver(REQUESTER_1, true);
//         address signer = makeAddr("signer");

//         // Try to remove a signer that was never added
//         vm.startPrank(REQUESTER_1);
//         vm.expectRevert(abi.encodeWithSelector(ISuccinctVApp.InvalidSigner.selector));
//         SuccinctVApp(VAPP).removeDelegatedSigner(signer);
//         vm.stopPrank();

//         // Verify no receipt was created
//         assertEq(SuccinctVApp(VAPP).currentReceipt(), 0);
//     }
}
