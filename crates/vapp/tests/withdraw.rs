mod common;

use alloy_primitives::U256;
use spn_vapp_core::{errors::VAppPanic, verifier::MockVerifier};

use crate::common::*;

#[test]
fn test_withdraw_basic() {
    let mut test = setup();
    let account = test.requester.address();
    let auctioneer = test.state.auctioneer;

    // Set up initial balance with deposit (101 PROVE = 101e18 wei).
    let initial_balance = U256::from(101) * U256::from(10).pow(U256::from(18));
    let deposit_tx = deposit_tx(account, initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&mut test, account, initial_balance);

    // Execute basic withdraw (60 PROVE).
    let withdraw_amount = U256::from(60) * U256::from(10).pow(U256::from(18));
    let withdraw_tx = withdraw_tx(&test.requester, account, withdraw_amount, 0);
    let receipt = test.state.execute::<MockVerifier>(&withdraw_tx).unwrap();

    // Verify the balance was deducted correctly (60 withdrawn + 1 auctioneer fee = 61 PROVE
    // deducted).
    let expected_balance = U256::from(40) * U256::from(10).pow(U256::from(18)); // 101 - 61 = 40 PROVE
    let auctioneer_fee = U256::from(10).pow(U256::from(18)); // 1 PROVE
    assert_account_balance(&mut test, account, expected_balance);
    assert_account_balance(&mut test, auctioneer, auctioneer_fee);
    assert_withdraw_receipt(&receipt, account, withdraw_amount);
    assert_state_counters(&test, 3, 2, 0, 1);
}

#[test]
fn test_withdraw_partial() {
    let mut test = setup();
    let account = test.requester.address();
    let auctioneer = test.state.auctioneer;

    // Set up initial balance with deposit (503 PROVE to cover 3 withdrawals with fees).
    let initial_balance = U256::from(503) * U256::from(10).pow(U256::from(18));
    let deposit_tx = deposit_tx(account, initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute first partial withdraw (100 PROVE).
    let withdraw_amount_1 = U256::from(100) * U256::from(10).pow(U256::from(18));
    let withdraw1 = withdraw_tx(&test.requester, account, withdraw_amount_1, 0);
    let receipt1 = test.state.execute::<MockVerifier>(&withdraw1).unwrap();
    let balance_after_1 = U256::from(402) * U256::from(10).pow(U256::from(18)); // 503 - 100 - 1 fee = 402 PROVE
    let auctioneer_fee = U256::from(10).pow(U256::from(18)); // 1 PROVE
    assert_account_balance(&mut test, account, balance_after_1);
    assert_account_balance(&mut test, auctioneer, auctioneer_fee);
    assert_withdraw_receipt(&receipt1, account, withdraw_amount_1);

    // Execute second partial withdraw (200 PROVE).
    let withdraw_amount_2 = U256::from(200) * U256::from(10).pow(U256::from(18));
    let withdraw2 = withdraw_tx(&test.requester, account, withdraw_amount_2, 0);
    let receipt2 = test.state.execute::<MockVerifier>(&withdraw2).unwrap();
    let balance_after_2 = U256::from(201) * U256::from(10).pow(U256::from(18)); // 402 - 200 - 1 fee = 201 PROVE
    let auctioneer_fee_2 = U256::from(2) * U256::from(10).pow(U256::from(18)); // 2 PROVE total
    assert_account_balance(&mut test, account, balance_after_2);
    assert_account_balance(&mut test, auctioneer, auctioneer_fee_2);
    assert_withdraw_receipt(&receipt2, account, withdraw_amount_2);

    // Execute third partial withdraw (50 PROVE).
    let withdraw_amount_3 = U256::from(50) * U256::from(10).pow(U256::from(18));
    let withdraw3 = withdraw_tx(&test.requester, account, withdraw_amount_3, 0);
    let receipt3 = test.state.execute::<MockVerifier>(&withdraw3).unwrap();
    let balance_after_3 = U256::from(150) * U256::from(10).pow(U256::from(18)); // 201 - 50 - 1 fee = 150 PROVE
    let auctioneer_fee_3 = U256::from(3) * U256::from(10).pow(U256::from(18)); // 3 PROVE total
    assert_account_balance(&mut test, account, balance_after_3);
    assert_account_balance(&mut test, auctioneer, auctioneer_fee_3);
    assert_withdraw_receipt(&receipt3, account, withdraw_amount_3);
}

#[test]
fn test_withdraw_exact_balance() {
    let mut test = setup();
    let account = test.requester.address();
    let auctioneer = test.state.auctioneer;

    // Set up initial balance with deposit (790 PROVE).
    let initial_balance = U256::from(790) * U256::from(10).pow(U256::from(18));
    let deposit_tx = deposit_tx(account, initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute withdraw for balance minus fee (789 PROVE).
    let withdraw_amount = U256::from(789) * U256::from(10).pow(U256::from(18));
    let withdraw_tx = withdraw_tx(&test.requester, account, withdraw_amount, 0);
    let receipt = test.state.execute::<MockVerifier>(&withdraw_tx).unwrap();

    // Verify exact amount was withdrawn, leaving zero balance.
    assert_account_balance(&mut test, account, U256::ZERO);
    let auctioneer_fee = U256::from(10).pow(U256::from(18)); // 1 PROVE
    assert_account_balance(&mut test, auctioneer, auctioneer_fee);
    assert_withdraw_receipt(&receipt, account, withdraw_amount);
}

#[test]
fn test_withdraw_insufficient_balance() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance with deposit (100 PROVE).
    let initial_balance = U256::from(100) * U256::from(10).pow(U256::from(18));
    let deposit_tx = deposit_tx(account, initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to withdraw exactly balance (which will fail due to auctioneer fee).
    let withdraw_amount = U256::from(100) * U256::from(10).pow(U256::from(18));
    let withdraw_tx = withdraw_tx(&test.requester, account, withdraw_amount, 0);
    let result = test.state.execute::<MockVerifier>(&withdraw_tx);

    assert!(matches!(result, Err(VAppPanic::InsufficientBalance { .. })));
}

#[test]
fn test_withdraw_zero_balance_account() {
    let mut test = setup();
    let account = test.requester.address();

    // Try to withdraw from account with zero balance (no prior deposit).
    let withdraw_amount = U256::from(1) * U256::from(10).pow(U256::from(18)); // 1 PROVE
    let withdraw_tx = withdraw_tx(&test.requester, account, withdraw_amount, 0);
    let result = test.state.execute::<MockVerifier>(&withdraw_tx);

    assert!(matches!(result, Err(VAppPanic::InsufficientBalance { .. })));
}

#[test]
fn test_withdraw_insufficient_for_auctioneer_fee() {
    let mut test = setup();
    let account = test.requester.address();

    // Set up initial balance with exactly 1 PROVE (only enough for fee, not withdrawal).
    let initial_balance = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx = deposit_tx(account, initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to withdraw 1 PROVE (will fail because need 2 total: 1 for withdrawal + 1 for fee).
    let withdraw_amount = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let withdraw_tx = withdraw_tx(&test.requester, account, withdraw_amount, 0);
    let result = test.state.execute::<MockVerifier>(&withdraw_tx);

    assert!(matches!(result, Err(VAppPanic::InsufficientBalance { .. })));
}
