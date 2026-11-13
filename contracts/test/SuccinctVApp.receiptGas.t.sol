// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SuccinctVAppTest} from "./SuccinctVApp.t.sol";
import {SuccinctVApp} from "../src/SuccinctVApp.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {MockStaking} from "../src/mocks/MockStaking.sol";
import {MockVerifier} from "../src/mocks/MockVerifier.sol";
import {IntermediateSuccinct} from "../src/tokens/IntermediateSuccinct.sol";
import {ERC1967Proxy} from "../lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    Receipt as TxReceipt,
    StepPublicValues,
    TransactionStatus,
    TransactionVariant,
    WithdrawAction
} from "../src/libraries/PublicValues.sol";

contract SuccinctVAppReceiptGasTest is SuccinctVAppTest {
    function test_ReceiptGas_ThousandWithdrawalsExceedTenMillionGas() public {
        mockCall(true);
        MockERC20(PROVE).mint(VAPP, 1_000);
        bytes memory values = _withdrawals(1_000, fixture.oldRoot, bytes32(uint256(1)), false);

        vm.prank(AUCTIONEER);
        (bool ok,) = VAPP.call{gas: 10_000_000}(
            abi.encodeCall(SuccinctVApp.step, (values, jsonFixture.proof))
        );
        assertFalse(ok, "batch must exceed the ten million gas budget");
        assertEq(SuccinctVApp(VAPP).blockNumber(), 0);
        assertEq(SuccinctVApp(VAPP).root(), fixture.oldRoot);
        assertEq(MockERC20(PROVE).balanceOf(ALICE), 0);

        vm.prank(AUCTIONEER);
        (ok,) = VAPP.call{gas: 30_000_000}(
            abi.encodeCall(SuccinctVApp.step, (values, jsonFixture.proof))
        );
        assertTrue(ok, "same batch succeeds with more gas");
        assertEq(SuccinctVApp(VAPP).blockNumber(), 1);
        assertEq(MockERC20(PROVE).balanceOf(ALICE), 1_000);
    }

    function test_ReceiptGas_SplitWithdrawalsAdvanceConsecutiveRoots() public {
        mockCall(true);
        MockERC20(PROVE).mint(VAPP, 1_000);
        uint256 remaining = 1_000;
        uint64 step;
        bytes32 root = fixture.oldRoot;
        while (remaining > 0) {
            uint256 count = remaining > 32 ? 32 : remaining;
            bytes32 nextRoot = bytes32(uint256(++step));
            bytes memory values = _withdrawals(count, root, nextRoot, false);
            vm.prank(AUCTIONEER);
            (bool ok,) = VAPP.call{gas: 8_000_000}(
                abi.encodeCall(SuccinctVApp.step, (values, jsonFixture.proof))
            );
            assertTrue(ok, "bounded withdrawal prefix must fit");
            assertEq(SuccinctVApp(VAPP).blockNumber(), step);
            assertEq(SuccinctVApp(VAPP).root(), nextRoot);
            root = nextRoot;
            remaining -= count;
        }
        assertEq(step, 32);
        assertEq(MockERC20(PROVE).balanceOf(ALICE), 1_000);
        assertEq(MockERC20(PROVE).balanceOf(VAPP), 0);
    }

    function test_ReceiptGas_ColdRecipientsFitBoundedPrefix() public {
        mockCall(true);
        MockERC20(PROVE).mint(VAPP, 32);
        bytes memory values = _withdrawals(32, fixture.oldRoot, bytes32(uint256(1)), true);
        vm.prank(AUCTIONEER);
        (bool ok,) = VAPP.call{gas: 7_000_000}(
            abi.encodeCall(SuccinctVApp.step, (values, jsonFixture.proof))
        );
        assertTrue(ok, "cold balances fit with room for verification and calldata");
        for (uint256 i = 0; i < 32; i++) {
            assertEq(MockERC20(PROVE).balanceOf(address(uint160(i + 100))), 1);
        }
    }

    function _withdrawals(uint256 count, bytes32 oldRoot, bytes32 newRoot, bool distinct)
        internal
        view
        returns (bytes memory)
    {
        TxReceipt[] memory receipts = new TxReceipt[](count);
        for (uint256 i = 0; i < count; i++) {
            receipts[i] = TxReceipt({
                variant: TransactionVariant.Withdraw,
                status: TransactionStatus.Completed,
                onchainTxId: type(uint64).max,
                action: abi.encode(
                    WithdrawAction({
                        account: distinct ? address(uint160(i + 100)) : ALICE, amount: 1
                    })
                )
            });
        }
        return abi.encode(
            StepPublicValues({
                oldRoot: oldRoot,
                newRoot: newRoot,
                timestamp: uint64(block.timestamp),
                receipts: receipts
            })
        );
    }
}

contract SuccinctVAppReceiptGasVaultTest is Test {
    SuccinctVApp internal vapp;
    MockERC20 internal prove;
    IntermediateSuccinct internal iProve;
    address[] internal vaults;
    bytes32 internal constant ROOT = bytes32(uint256(100));

    function setUp() public {
        prove = new MockERC20("Succinct", "PROVE", 18);
        address stakingAddress =
            vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 1);
        iProve = new IntermediateSuccinct(address(prove), stakingAddress);
        MockStaking staking =
            new MockStaking(address(1), address(0), address(prove), address(iProve), address(2));
        assertEq(address(staking), stakingAddress);
        vapp = SuccinctVApp(address(new ERC1967Proxy(address(new SuccinctVApp()), "")));
        vapp.initialize(
            address(this),
            address(prove),
            address(iProve),
            address(this),
            address(staking),
            address(new MockVerifier()),
            1,
            bytes32(uint256(1)),
            ROOT
        );
        staking.setVApp(address(vapp));
        for (uint256 i = 0; i < 32; i++) {
            // Real prover constructors self-delegate, exercising distinct voting checkpoints.
            vaults.push(staking.createProver(address(uint160(i + 100)), 1_000));
        }
        prove.mint(address(vapp), 32);
    }

    function test_ReceiptGas_ColdVaultRewardsFitBoundedPrefix() public {
        TxReceipt[] memory receipts = new TxReceipt[](vaults.length);
        for (uint256 i = 0; i < receipts.length; i++) {
            receipts[i] = TxReceipt({
                variant: TransactionVariant.Withdraw,
                status: TransactionStatus.Completed,
                onchainTxId: type(uint64).max,
                action: abi.encode(WithdrawAction({account: vaults[i], amount: 1}))
            });
        }
        bytes memory values = abi.encode(
            StepPublicValues({
                oldRoot: ROOT,
                newRoot: bytes32(uint256(101)),
                timestamp: uint64(block.timestamp),
                receipts: receipts
            })
        );
        bytes memory data = abi.encodeCall(SuccinctVApp.step, (values, bytes("")));
        uint256 before = gasleft();
        (bool ok,) = address(vapp).call{gas: 7_000_000}(data);
        uint256 used = before - gasleft();
        assertTrue(ok, "real vault deposits and voting checkpoints must fit");
        // Include a conservative calldata floor and reserve for the real proof verifier.
        assertLt(used + 21_000 + 40 * data.length + 500_000, 8_000_000);
        assertEq(vapp.blockNumber(), 1);
        for (uint256 i = 0; i < vaults.length; i++) {
            assertEq(iProve.balanceOf(vaults[i]), 1);
            assertEq(iProve.getVotes(vaults[i]), 1);
        }
    }
}
