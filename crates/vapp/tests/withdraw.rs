mod common;

use alloy_primitives::U256;
use spn_vapp_core::{
    errors::VAppPanic, receipts::VAppReceipt, sol::TransactionStatus, verifier::MockVerifier,
};

use crate::common::*;

#[test]
fn test_withdraw_basic() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance with deposit.
    let deposit_tx = deposit_tx(account, U256::from(100), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&mut test, account, U256::from(100));

    // Execute basic withdraw.
    let withdraw_tx = withdraw_tx(account, U256::from(60), 0, 2, 2);
    let receipt = test.state.execute::<MockVerifier>(&withdraw_tx).unwrap();

    // Verify the balance was deducted correctly.
    assert_account_balance(&mut test, account, U256::from(40));
    assert_withdraw_receipt(&receipt, account, U256::from(60), 2);
    assert_state_counters(&test, 3, 3, 0, 2);
}

#[test]
fn test_withdraw_partial() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance with deposit.
    let deposit_tx = deposit_tx(account, U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute first partial withdraw.
    let withdraw1 = withdraw_tx(account, U256::from(100), 0, 2, 2);
    let receipt1 = test.state.execute::<MockVerifier>(&withdraw1).unwrap();
    assert_account_balance(&mut test, account, U256::from(400));
    assert_withdraw_receipt(&receipt1, account, U256::from(100), 2);

    // Execute second partial withdraw.
    let withdraw2 = withdraw_tx(account, U256::from(200), 0, 3, 3);
    let receipt2 = test.state.execute::<MockVerifier>(&withdraw2).unwrap();
    assert_account_balance(&mut test, account, U256::from(200));
    assert_withdraw_receipt(&receipt2, account, U256::from(200), 3);

    // Execute third partial withdraw.
    let withdraw3 = withdraw_tx(account, U256::from(50), 1, 1, 4);
    let receipt3 = test.state.execute::<MockVerifier>(&withdraw3).unwrap();
    assert_account_balance(&mut test, account, U256::from(150));
    assert_withdraw_receipt(&receipt3, account, U256::from(50), 4);
}

#[test]
fn test_withdraw_full_balance_with_max() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance with deposit.
    let initial_amount = U256::from(12345);
    let deposit_tx = deposit_tx(account, initial_amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&mut test, account, initial_amount);

    // Execute withdraw with U256::MAX to drain entire balance.
    let withdraw_tx = withdraw_tx(account, U256::MAX, 0, 2, 2);
    let receipt = test.state.execute::<MockVerifier>(&withdraw_tx).unwrap();

    // Verify entire balance was withdrawn.
    assert_account_balance(&mut test, account, U256::ZERO);
    // Receipt should show the actual withdrawn amount, not U256::MAX.
    assert_withdraw_receipt(&receipt, account, initial_amount, 2);
    assert_state_counters(&test, 3, 3, 0, 2);
}

#[test]
fn test_withdraw_exact_balance() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance with deposit.
    let amount = U256::from(789);
    let deposit_tx = deposit_tx(account, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute withdraw for exact balance amount.
    let withdraw_tx = withdraw_tx(account, amount, 0, 2, 2);
    let receipt = test.state.execute::<MockVerifier>(&withdraw_tx).unwrap();

    // Verify exact amount was withdrawn, leaving zero balance.
    assert_account_balance(&mut test, account, U256::ZERO);
    assert_withdraw_receipt(&receipt, account, amount, 2);
}

#[test]
fn test_withdraw_insufficient_balance() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance with deposit.
    let deposit_tx = deposit_tx(account, U256::from(100), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to withdraw more than balance.
    let withdraw_tx = withdraw_tx(account, U256::from(150), 0, 2, 2);
    let result = test.state.execute::<MockVerifier>(&withdraw_tx);

    // Verify the transaction succeeds but reverts.
    let receipt = result.unwrap().unwrap();
    match &receipt {
        VAppReceipt::Withdraw(withdraw) => {
            assert_eq!(withdraw.action.account, account);
            assert_eq!(withdraw.action.amount, U256::from(150));
            assert_eq!(withdraw.onchain_tx_id, 2);
            assert_eq!(withdraw.status, TransactionStatus::Reverted);
        }
        _ => panic!("Expected a withdraw receipt"),
    }

    // Verify state remains unchanged after error (onchain counters increment, but tx_id does not).
    assert_account_balance(&mut test, account, U256::from(100));
    assert_state_counters(&test, 3, 3, 0, 2);
}

#[test]
fn test_withdraw_zero_balance_account() {
    let mut test = setup();
    let account = test.requester.address();

    // Try to withdraw from account with zero balance (no prior deposit).
    let withdraw_tx = withdraw_tx(account, U256::from(1), 0, 1, 1);
    let result = test.state.execute::<MockVerifier>(&withdraw_tx);

    // Verify the transaction succeeds but reverts.
    let receipt = result.unwrap().unwrap();
    match &receipt {
        VAppReceipt::Withdraw(withdraw) => {
            assert_eq!(withdraw.action.account, account);
            assert_eq!(withdraw.action.amount, U256::from(1));
            assert_eq!(withdraw.onchain_tx_id, 1);
            assert_eq!(withdraw.status, TransactionStatus::Reverted);
        }
        _ => panic!("Expected a withdraw receipt"),
    }

    // Verify state counters behavior for failed transaction (onchain counters increment, but tx_id does not).
    assert_state_counters(&test, 2, 2, 0, 1);
}

#[test]
fn test_withdraw_onchain_tx_out_of_order() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance and execute first withdraw.
    let deposit_tx = deposit_tx(account, U256::from(200), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let withdraw1 = withdraw_tx(account, U256::from(50), 0, 2, 2);
    test.state.execute::<MockVerifier>(&withdraw1).unwrap();

    // Try to execute withdraw with wrong onchain_tx (should be 3, but using 5).
    let withdraw2 = withdraw_tx(account, U256::from(50), 0, 3, 5);
    let result = test.state.execute::<MockVerifier>(&withdraw2);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::OnchainTxOutOfOrder { expected: 3, actual: 5 })));

    // Verify state remains unchanged after error.
    assert_account_balance(&mut test, account, U256::from(150));
    assert_state_counters(&test, 3, 3, 0, 2);
}

#[test]
fn test_withdraw_block_number_regression() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance at block 10.
    let deposit_tx = deposit_tx(account, U256::from(200), 10, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to execute withdraw at earlier block (regression).
    let withdraw_tx = withdraw_tx(account, U256::from(50), 8, 1, 2);
    let result = test.state.execute::<MockVerifier>(&withdraw_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::BlockNumberOutOfOrder { expected: 10, actual: 8 })));

    // Verify state remains unchanged after error.
    assert_account_balance(&mut test, account, U256::from(200));
    assert_state_counters(&test, 2, 2, 10, 1);
}

#[test]
fn test_withdraw_log_index_out_of_order() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance at block 0, log_index 10.
    let deposit_tx = deposit_tx(account, U256::from(200), 0, 10, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to execute withdraw at same block with same log_index.
    let withdraw1 = withdraw_tx(account, U256::from(50), 0, 10, 2);
    let result = test.state.execute::<MockVerifier>(&withdraw1);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::LogIndexOutOfOrder { current: 10, next: 10 })));

    // Try with log_index lower than current.
    let withdraw2 = withdraw_tx(account, U256::from(50), 0, 5, 2);
    let result = test.state.execute::<MockVerifier>(&withdraw2);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::LogIndexOutOfOrder { current: 10, next: 5 })));

    // Verify state remains unchanged after error.
    assert_account_balance(&mut test, account, U256::from(200));
    assert_state_counters(&test, 2, 2, 0, 10);
}

#[test]
fn test_withdraw_log_index_valid_progression() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance at block 0, log_index 5.
    let deposit_tx = deposit_tx(account, U256::from(300), 0, 5, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute withdraw at same block with higher log_index (valid).
    let withdraw1 = withdraw_tx(account, U256::from(100), 0, 6, 2);
    let receipt1 = test.state.execute::<MockVerifier>(&withdraw1).unwrap();

    // Verify balance deduction and state updates.
    assert_account_balance(&mut test, account, U256::from(200));
    assert_withdraw_receipt(&receipt1, account, U256::from(100), 2);
    assert_state_counters(&test, 3, 3, 0, 6);

    // Execute withdraw at higher block (log_index can be anything).
    let withdraw2 = withdraw_tx(account, U256::from(50), 1, 1, 3);
    let receipt2 = test.state.execute::<MockVerifier>(&withdraw2).unwrap();

    // Verify final state after block progression.
    assert_account_balance(&mut test, account, U256::from(150));
    assert_withdraw_receipt(&receipt2, account, U256::from(50), 3);
    assert_state_counters(&test, 4, 4, 1, 1);
}
