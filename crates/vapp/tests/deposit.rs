mod common;

use alloy_primitives::U256;
use spn_vapp_core::{errors::VAppPanic, verifier::MockVerifier};

use crate::common::*;

#[test]
fn test_deposit_basic() {
    let mut test = setup();
    let account = test.requester.address();
    let amount = U256::from(100);

    // Create and execute a basic deposit tx.
    let tx = deposit_tx(account, amount, 0, 1, 1);
    let receipt = test.state.execute::<MockVerifier>(&tx).unwrap();

    // Verify the account balance was updated correctly.
    assert_account_balance(&mut test, account, amount);
    assert_deposit_receipt(&receipt, account, amount, 1);

    // Verify state counters were incremented.
    assert_state_counters(&test, 2, 2, 0, 1);
}

#[test]
fn test_deposit_multiple_same_account() {
    let mut test = setup();
    let account = test.requester.address();

    // Execute first deposit.
    let tx1 = deposit_tx(account, U256::from(100), 0, 1, 1);
    let receipt1 = test.state.execute::<MockVerifier>(&tx1).unwrap();
    assert_deposit_receipt(&receipt1, account, U256::from(100), 1);
    assert_account_balance(&mut test, account, U256::from(100));

    // Execute second deposit to same account.
    let tx2 = deposit_tx(account, U256::from(200), 0, 2, 2);
    let receipt2 = test.state.execute::<MockVerifier>(&tx2).unwrap();
    assert_deposit_receipt(&receipt2, account, U256::from(200), 2);
    assert_account_balance(&mut test, account, U256::from(300));

    // Execute third deposit to same account.
    let tx3 = deposit_tx(account, U256::from(50), 1, 1, 3);
    let receipt3 = test.state.execute::<MockVerifier>(&tx3).unwrap();
    assert_deposit_receipt(&receipt3, account, U256::from(50), 3);
    assert_account_balance(&mut test, account, U256::from(350));
}

#[test]
fn test_deposit_multiple_different_accounts() {
    let mut test = setup();
    let account1 = test.requester.address();
    let account2 = test.fulfiller.address();
    let account3 = test.auctioneer.address();

    // Execute deposit to account1.
    let tx1 = deposit_tx(account1, U256::from(100), 0, 1, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();
    assert_account_balance(&mut test, account1, U256::from(100));

    // Execute deposit to account2.
    let tx2 = deposit_tx(account2, U256::from(200), 0, 2, 2);
    test.state.execute::<MockVerifier>(&tx2).unwrap();
    assert_account_balance(&mut test, account2, U256::from(200));

    // Execute deposit to account3.
    let tx3 = deposit_tx(account3, U256::from(300), 1, 1, 3);
    test.state.execute::<MockVerifier>(&tx3).unwrap();
    assert_account_balance(&mut test, account3, U256::from(300));

    // Verify all accounts maintain correct balances.
    assert_account_balance(&mut test, account1, U256::from(100));
    assert_account_balance(&mut test, account2, U256::from(200));
    assert_account_balance(&mut test, account3, U256::from(300));
}

#[test]
fn test_deposit_large_amounts() {
    let mut test = setup();
    let account = test.requester.address();

    // Execute deposit with maximum U256 value.
    let max_amount = U256::MAX;
    let tx = deposit_tx(account, max_amount, 0, 1, 1);
    let receipt = test.state.execute::<MockVerifier>(&tx).unwrap();

    // Verify maximum amount deposit succeeded.
    assert_account_balance(&mut test, account, max_amount);
    assert_deposit_receipt(&receipt, account, max_amount, 1);
}

#[test]
fn test_deposit_zero_amount() {
    let mut test = setup();
    let account = test.requester.address();

    // Execute deposit with zero amount.
    let tx = deposit_tx(account, U256::ZERO, 0, 1, 1);
    let receipt = test.state.execute::<MockVerifier>(&tx).unwrap();

    // Verify zero amount deposit succeeded.
    assert_account_balance(&mut test, account, U256::ZERO);
    assert_deposit_receipt(&receipt, account, U256::ZERO, 1);
}

#[test]
fn test_deposit_onchain_tx_out_of_order() {
    let mut test = setup();
    let account = test.requester.address();

    // Execute first deposit.
    let tx1 = deposit_tx(account, U256::from(100), 0, 1, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();

    // Try to execute deposit with wrong onchain_tx (should be 2, but using 3).
    let tx2 = deposit_tx(account, U256::from(100), 0, 2, 3);
    let result = test.state.execute::<MockVerifier>(&tx2);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::OnchainTxOutOfOrder { expected: 2, actual: 3 })));

    // Verify state remains unchanged after error.
    assert_account_balance(&mut test, account, U256::from(100));
    assert_state_counters(&test, 2, 2, 0, 1);
}

#[test]
fn test_deposit_block_number_regression() {
    let mut test = setup();
    let account = test.requester.address();

    // Execute first deposit at block 5.
    let tx1 = deposit_tx(account, U256::from(100), 5, 1, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();

    // Try to execute deposit at earlier block (regression).
    let tx2 = deposit_tx(account, U256::from(100), 3, 1, 2);
    let result = test.state.execute::<MockVerifier>(&tx2);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::BlockNumberOutOfOrder { expected: 5, actual: 3 })));

    // Verify state remains unchanged after error.
    assert_account_balance(&mut test, account, U256::from(100));
    assert_state_counters(&test, 2, 2, 5, 1);
}

#[test]
fn test_deposit_log_index_out_of_order() {
    let mut test = setup();
    let account = test.requester.address();

    // Execute first deposit at block 0, log_index 5.
    let tx1 = deposit_tx(account, U256::from(100), 0, 5, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();

    // Try to execute deposit at same block with same log_index.
    let tx2 = deposit_tx(account, U256::from(100), 0, 5, 2);
    let result = test.state.execute::<MockVerifier>(&tx2);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::LogIndexOutOfOrder { current: 5, next: 5 })));

    // Try with log_index lower than current.
    let tx3 = deposit_tx(account, U256::from(100), 0, 3, 2);
    let result = test.state.execute::<MockVerifier>(&tx3);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::LogIndexOutOfOrder { current: 5, next: 3 })));

    // Verify state remains unchanged after error.
    assert_account_balance(&mut test, account, U256::from(100));
    assert_state_counters(&test, 2, 2, 0, 5);
}

#[test]
fn test_deposit_log_index_valid_progression() {
    let mut test = setup();
    let account = test.requester.address();

    // Execute first deposit at block 0, log_index 5.
    let tx1 = deposit_tx(account, U256::from(100), 0, 5, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();

    // Execute second deposit at same block with higher log_index (valid).
    let tx2 = deposit_tx(account, U256::from(100), 0, 6, 2);
    let receipt2 = test.state.execute::<MockVerifier>(&tx2).unwrap();

    // Verify balance accumulation and state updates.
    assert_account_balance(&mut test, account, U256::from(200));
    assert_deposit_receipt(&receipt2, account, U256::from(100), 2);
    assert_eq!(test.state.onchain_log_index, 6);

    // Execute third deposit at higher block (log_index can be anything).
    let tx3 = deposit_tx(account, U256::from(100), 1, 1, 3);
    let receipt3 = test.state.execute::<MockVerifier>(&tx3).unwrap();

    // Verify final state after block progression.
    assert_account_balance(&mut test, account, U256::from(300));
    assert_deposit_receipt(&receipt3, account, U256::from(100), 3);
    assert_state_counters(&test, 4, 4, 1, 1);
}
