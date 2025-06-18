mod common;

use alloy_primitives::U256;
use spn_vapp_core::{errors::VAppPanic, verifier::MockVerifier};

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
    let withdraw_tx = withdraw_tx(&test.requester, account, U256::from(60), 0);
    let receipt = test.state.execute::<MockVerifier>(&withdraw_tx).unwrap();

    // Verify the balance was deducted correctly.
    assert_account_balance(&mut test, account, U256::from(40));
    assert_withdraw_receipt(&receipt, account, U256::from(60));
    assert_state_counters(&test, 3, 2, 0, 1);
}

#[test]
fn test_withdraw_partial() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance with deposit.
    let deposit_tx = deposit_tx(account, U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute first partial withdraw.
    let withdraw1 = withdraw_tx(&test.requester, account, U256::from(100), 0);
    let receipt1 = test.state.execute::<MockVerifier>(&withdraw1).unwrap();
    assert_account_balance(&mut test, account, U256::from(400));
    assert_withdraw_receipt(&receipt1, account, U256::from(100));

    // Execute second partial withdraw.
    let withdraw2 = withdraw_tx(&test.requester, account, U256::from(200), 0);
    let receipt2 = test.state.execute::<MockVerifier>(&withdraw2).unwrap();
    assert_account_balance(&mut test, account, U256::from(200));
    assert_withdraw_receipt(&receipt2, account, U256::from(200));

    // Execute third partial withdraw.
    let withdraw3 = withdraw_tx(&test.requester, account, U256::from(50), 0);
    let receipt3 = test.state.execute::<MockVerifier>(&withdraw3).unwrap();
    assert_account_balance(&mut test, account, U256::from(150));
    assert_withdraw_receipt(&receipt3, account, U256::from(50));
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
    let withdraw_tx = withdraw_tx(&test.requester, account, amount, 0);
    let receipt = test.state.execute::<MockVerifier>(&withdraw_tx).unwrap();

    // Verify exact amount was withdrawn, leaving zero balance.
    assert_account_balance(&mut test, account, U256::ZERO);
    assert_withdraw_receipt(&receipt, account, amount);
}

#[test]
fn test_withdraw_insufficient_balance() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance with deposit.
    let deposit_tx = deposit_tx(account, U256::from(100), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to withdraw more than balance.
    let withdraw_tx = withdraw_tx(&test.requester, account, U256::from(150), 0);
    let result = test.state.execute::<MockVerifier>(&withdraw_tx);

    assert!(matches!(result, Err(VAppPanic::InsufficientBalance { .. })));
}

#[test]
fn test_withdraw_zero_balance_account() {
    let mut test = setup();
    let account = test.requester.address();

    // Try to withdraw from account with zero balance (no prior deposit).
    let withdraw_tx = withdraw_tx(&test.requester, account, U256::from(1), 0);
    let result = test.state.execute::<MockVerifier>(&withdraw_tx);

    assert!(matches!(result, Err(VAppPanic::InsufficientBalance { .. })));
}
