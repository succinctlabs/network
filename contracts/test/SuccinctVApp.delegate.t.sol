// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {Receipts} from "../src/libraries/Receipts.sol";
import {
    Step,
    TransactionStatus,
    Receipt as VAppReceipt,
    TransactionVariant,
    DepositTransaction,
    WithdrawTransaction,
    CreateProverTransaction
} from "../src/libraries/PublicValues.sol";
import {ISuccinctVApp} from "../src/interfaces/ISuccinctVApp.sol";
import {MockStaking} from "../src/mocks/MockStaking.sol";
import {console} from "forge-std/console.sol";

contract SuccinctVAppDelegateTest is SuccinctVAppTest {
    function test_Prover_WhenProverCreated() public {
        // Create the prover, this emits a Prover action for the prover owner being
        // a delegate of the prover.
        vm.expectEmit(true, true, true, false);
        emit ISuccinctVApp.TransactionPending(1, TransactionVariant.CreateProver, bytes(""));
        vm.prank(ALICE);
        address aliceProver = MockStaking(STAKING).createProver(ALICE, STAKER_FEE_BIPS);

        // The expected action data for alice creating a prover.
        bytes memory expectedProverData = abi.encode(
            CreateProverTransaction({
                prover: aliceProver,
                owner: ALICE,
                stakerFeeBips: STAKER_FEE_BIPS
            })
        );

        (TransactionVariant actionType, TransactionStatus status,, bytes memory data) =
            SuccinctVApp(VAPP).transactions(SuccinctVApp(VAPP).currentOnchainTx());
        assertEq(uint8(actionType), uint8(TransactionVariant.CreateProver));
        assertEq(uint8(status), uint8(TransactionStatus.Pending));
        assertEq(data, expectedProverData);

        // Process the first setDelegatedSigner action through state update
        Step memory publicValues1 = Step({
            txId: 2,
            receipts: new VAppReceipt[](1),
            oldRoot: fixture.oldRoot,
            newRoot: bytes32(uint256(1)),
            timestamp: uint64(block.timestamp)
        });
        publicValues1.receipts[0] = VAppReceipt({
            variant: TransactionVariant.CreateProver,
            status: TransactionStatus.Completed,
            onchainTx: SuccinctVApp(VAPP).currentOnchainTx(),
            data: expectedProverData
        });

        mockCall(true);
        vm.expectEmit(true, true, true, true);
        emit ISuccinctVApp.Block(1, publicValues1.newRoot, publicValues1.oldRoot);
        SuccinctVApp(VAPP).step(abi.encode(publicValues1), jsonFixture.proof);

        // Verify receipt status updated
        (, status,,) = SuccinctVApp(VAPP).transactions(SuccinctVApp(VAPP).currentOnchainTx());
        assertEq(uint8(status), uint8(TransactionStatus.Completed));
        // assertEq(SuccinctVApp(VAPP).finalizedOnchainTx(), 1);
    }
}
