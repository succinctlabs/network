// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Receipts} from "../src/libraries/Receipts.sol";
import {
    Transaction,
    Receipt as TxReceipt,
    TransactionVariant,
    TransactionStatus,
    Deposit,
    Withdraw,
    CreateProver
} from "../src/libraries/PublicValues.sol";

// Wrapper contract to test internal library functions
contract ReceiptsWrapper {
    function assertEq(Transaction memory _transaction, TxReceipt memory _receipt) external pure {
        Receipts.assertEq(_transaction, _receipt);
    }
}

contract ReceiptsTest is Test {
    ReceiptsWrapper wrapper;
    // Test addresses
    address constant ALICE = address(0x1);
    address constant BOB = address(0x2);
    address constant PROVER = address(0x3);
    address constant OWNER = address(0x4);

    // Test amounts
    uint256 constant DEPOSIT_AMOUNT = 100 ether;
    uint256 constant WITHDRAW_AMOUNT = 50 ether;
    uint256 constant STAKER_FEE_BIPS = 1000;

    // Test transaction IDs
    uint64 constant TX_ID = 12345;

    function setUp() public {
        wrapper = new ReceiptsWrapper();
    }

    // Helper functions to create test data
    function createDepositTransaction(address account, uint256 amount)
        internal
        pure
        returns (Transaction memory)
    {
        Deposit memory deposit = Deposit({account: account, amount: amount});
        return Transaction({
            variant: TransactionVariant.Deposit,
            status: TransactionStatus.Completed,
            onchainTxId: TX_ID,
            action: abi.encode(deposit)
        });
    }

    function createDepositReceipt(address account, uint256 amount) internal pure returns (TxReceipt memory) {
        Deposit memory deposit = Deposit({account: account, amount: amount});
        return TxReceipt({
            variant: TransactionVariant.Deposit,
            status: TransactionStatus.Completed,
            onchainTxId: TX_ID,
            action: abi.encode(deposit)
        });
    }

    function createWithdrawTransaction(address account, uint256 amount)
        internal
        pure
        returns (Transaction memory)
    {
        Withdraw memory withdraw = Withdraw({account: account, amount: amount});
        return Transaction({
            variant: TransactionVariant.Withdraw,
            status: TransactionStatus.Completed,
            onchainTxId: TX_ID,
            action: abi.encode(withdraw)
        });
    }

    function createWithdrawReceipt(address account, uint256 amount) internal pure returns (TxReceipt memory) {
        Withdraw memory withdraw = Withdraw({account: account, amount: amount});
        return TxReceipt({
            variant: TransactionVariant.Withdraw,
            status: TransactionStatus.Completed,
            onchainTxId: TX_ID,
            action: abi.encode(withdraw)
        });
    }

    function createProverTransaction(address prover, address owner, uint256 stakerFeeBips)
        internal
        pure
        returns (Transaction memory)
    {
        CreateProver memory createProver =
            CreateProver({prover: prover, owner: owner, stakerFeeBips: stakerFeeBips});
        return Transaction({
            variant: TransactionVariant.CreateProver,
            status: TransactionStatus.Completed,
            onchainTxId: TX_ID,
            action: abi.encode(createProver)
        });
    }

    function createProverReceipt(address prover, address owner, uint256 stakerFeeBips)
        internal
        pure
        returns (TxReceipt memory)
    {
        CreateProver memory createProver =
            CreateProver({prover: prover, owner: owner, stakerFeeBips: stakerFeeBips});
        return TxReceipt({
            variant: TransactionVariant.CreateProver,
            status: TransactionStatus.Completed,
            onchainTxId: TX_ID,
            action: abi.encode(createProver)
        });
    }

    // Test cases for valid deposit assertions
    function test_AssertEq_ValidDeposit() public view {
        Transaction memory transaction = createDepositTransaction(ALICE, DEPOSIT_AMOUNT);
        TxReceipt memory receipt = createDepositReceipt(ALICE, DEPOSIT_AMOUNT);

        // Should not revert.
        wrapper.assertEq(transaction, receipt);
    }

    // Test cases for valid withdraw assertions
    function test_AssertEq_ValidWithdraw() public view {
        Transaction memory transaction = createWithdrawTransaction(ALICE, WITHDRAW_AMOUNT);
        TxReceipt memory receipt = createWithdrawReceipt(ALICE, WITHDRAW_AMOUNT);

        // Should not revert.
        wrapper.assertEq(transaction, receipt);
    }

    function test_AssertEq_ValidWithdraw_MaxUint256() public view {
        // When withdraw amount is max uint256, the validation should pass regardless of receipt amount.
        Transaction memory transaction = createWithdrawTransaction(ALICE, type(uint256).max);
        TxReceipt memory receipt = createWithdrawReceipt(ALICE, WITHDRAW_AMOUNT);

        // Should not revert.
        wrapper.assertEq(transaction, receipt);
    }

    // Test cases for valid CreateProver assertions
    function test_AssertEq_ValidCreateProver() public view {
        Transaction memory transaction = createProverTransaction(PROVER, OWNER, STAKER_FEE_BIPS);
        TxReceipt memory receipt = createProverReceipt(PROVER, OWNER, STAKER_FEE_BIPS);

        // Should not revert.
        wrapper.assertEq(transaction, receipt);
    }

    // Note: UnsupportedTransactionVariant error cannot be tested because Solidity prevents
    // passing invalid enum values at runtime. The error exists for defensive programming
    // but would only be reachable if the enum definition changes in the future.

    // Test cases for TransactionVariantMismatch errors
    function test_AssertEq_TransactionVariantMismatch_DepositTxWithdrawReceipt() public {
        Transaction memory transaction = createDepositTransaction(ALICE, DEPOSIT_AMOUNT);
        TxReceipt memory receipt = createWithdrawReceipt(ALICE, WITHDRAW_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                Receipts.TransactionVariantMismatch.selector,
                TransactionVariant.Deposit,
                TransactionVariant.Withdraw
            )
        );
        wrapper.assertEq(transaction, receipt);
    }

    function test_AssertEq_TransactionVariantMismatch_WithdrawTxDepositReceipt() public {
        Transaction memory transaction = createWithdrawTransaction(ALICE, WITHDRAW_AMOUNT);
        TxReceipt memory receipt = createDepositReceipt(ALICE, DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                Receipts.TransactionVariantMismatch.selector,
                TransactionVariant.Withdraw,
                TransactionVariant.Deposit
            )
        );
        wrapper.assertEq(transaction, receipt);
    }

    function test_AssertEq_TransactionVariantMismatch_ProverTxDepositReceipt() public {
        Transaction memory transaction = createProverTransaction(PROVER, OWNER, STAKER_FEE_BIPS);
        TxReceipt memory receipt = createDepositReceipt(ALICE, DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                Receipts.TransactionVariantMismatch.selector,
                TransactionVariant.CreateProver,
                TransactionVariant.Deposit
            )
        );
        wrapper.assertEq(transaction, receipt);
    }

    // Test cases for TransactionReceiptMismatch errors - Deposit
    function test_AssertEq_DepositMismatch_DifferentAccount() public {
        Transaction memory transaction = createDepositTransaction(ALICE, DEPOSIT_AMOUNT);
        TxReceipt memory receipt = createDepositReceipt(BOB, DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(Receipts.TransactionReceiptMismatch.selector, TransactionVariant.Deposit, TX_ID)
        );
        wrapper.assertEq(transaction, receipt);
    }

    function test_AssertEq_DepositMismatch_DifferentAmount() public {
        Transaction memory transaction = createDepositTransaction(ALICE, DEPOSIT_AMOUNT);
        TxReceipt memory receipt = createDepositReceipt(ALICE, DEPOSIT_AMOUNT + 1);

        vm.expectRevert(
            abi.encodeWithSelector(Receipts.TransactionReceiptMismatch.selector, TransactionVariant.Deposit, TX_ID)
        );
        wrapper.assertEq(transaction, receipt);
    }

    // Test cases for TransactionReceiptMismatch errors - Withdraw
    function test_AssertEq_WithdrawMismatch_DifferentAccount() public {
        Transaction memory transaction = createWithdrawTransaction(ALICE, WITHDRAW_AMOUNT);
        TxReceipt memory receipt = createWithdrawReceipt(BOB, WITHDRAW_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(Receipts.TransactionReceiptMismatch.selector, TransactionVariant.Withdraw, TX_ID)
        );
        wrapper.assertEq(transaction, receipt);
    }

    function test_AssertEq_WithdrawMismatch_DifferentAmount() public {
        Transaction memory transaction = createWithdrawTransaction(ALICE, WITHDRAW_AMOUNT);
        TxReceipt memory receipt = createWithdrawReceipt(ALICE, WITHDRAW_AMOUNT + 1);

        vm.expectRevert(
            abi.encodeWithSelector(Receipts.TransactionReceiptMismatch.selector, TransactionVariant.Withdraw, TX_ID)
        );
        wrapper.assertEq(transaction, receipt);
    }

    // Test cases for TransactionReceiptMismatch errors - CreateProver
    function test_AssertEq_ProverMismatch_DifferentProver() public {
        Transaction memory transaction = createProverTransaction(PROVER, OWNER, STAKER_FEE_BIPS);
        TxReceipt memory receipt = createProverReceipt(BOB, OWNER, STAKER_FEE_BIPS);

        vm.expectRevert(
            abi.encodeWithSelector(
                Receipts.TransactionReceiptMismatch.selector, TransactionVariant.CreateProver, TX_ID
            )
        );
        wrapper.assertEq(transaction, receipt);
    }

    function test_AssertEq_ProverMismatch_DifferentOwner() public {
        Transaction memory transaction = createProverTransaction(PROVER, OWNER, STAKER_FEE_BIPS);
        TxReceipt memory receipt = createProverReceipt(PROVER, BOB, STAKER_FEE_BIPS);

        vm.expectRevert(
            abi.encodeWithSelector(
                Receipts.TransactionReceiptMismatch.selector, TransactionVariant.CreateProver, TX_ID
            )
        );
        wrapper.assertEq(transaction, receipt);
    }

    function test_AssertEq_ProverMismatch_DifferentStakerFeeBips() public {
        Transaction memory transaction = createProverTransaction(PROVER, OWNER, STAKER_FEE_BIPS);
        TxReceipt memory receipt = createProverReceipt(PROVER, OWNER, STAKER_FEE_BIPS + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                Receipts.TransactionReceiptMismatch.selector, TransactionVariant.CreateProver, TX_ID
            )
        );
        wrapper.assertEq(transaction, receipt);
    }

    // Fuzz tests
    function testFuzz_AssertEq_Deposit(address account, uint256 amount) public view {
        Transaction memory transaction = createDepositTransaction(account, amount);
        TxReceipt memory receipt = createDepositReceipt(account, amount);

        // Should not revert.
        wrapper.assertEq(transaction, receipt);
    }

    function testFuzz_AssertEq_Withdraw(address account, uint256 amount) public view {
        Transaction memory transaction = createWithdrawTransaction(account, amount);
        TxReceipt memory receipt = createWithdrawReceipt(account, amount);

        // Should not revert.
        wrapper.assertEq(transaction, receipt);
    }

    function testFuzz_AssertEq_CreateProver(address prover, address owner, uint256 stakerFeeBips) public view {
        Transaction memory transaction = createProverTransaction(prover, owner, stakerFeeBips);
        TxReceipt memory receipt = createProverReceipt(prover, owner, stakerFeeBips);

        // Should not revert.
        wrapper.assertEq(transaction, receipt);
    }

    function testFuzz_AssertEq_WithdrawMaxUint256(address account, uint256 receiptAmount) public view {
        // When withdraw amount is max uint256, any receipt amount should pass.
        Transaction memory transaction = createWithdrawTransaction(account, type(uint256).max);
        TxReceipt memory receipt = createWithdrawReceipt(account, receiptAmount);

        // Should not revert.
        wrapper.assertEq(transaction, receipt);
    }
}