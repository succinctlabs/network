mod common;

use alloy_primitives::U256;
use spn_vapp_core::{errors::VAppPanic, verifier::MockVerifier};

use crate::common::*;

#[test]
fn test_withdraw_overflow_protection() {
    let mut test = setup();
    let account = test.requester.address();
    
    // Set account balance to U256::MAX using deposit.
    let max_balance = U256::MAX;
    let deposit_tx = deposit_tx(account, max_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&mut test, account, max_balance);
    
    // Create a withdrawal transaction that would overflow when adding the fee.
    // We want amount + AUCTIONEER_WITHDRAWAL_FEE to overflow.
    // AUCTIONEER_WITHDRAWAL_FEE is 1e18, so we use U256::MAX - 5e17 as the amount.
    let overflow_amount = U256::MAX - U256::from(5e17 as u64);
    let withdraw_tx = withdraw_tx(&test.requester, account, overflow_amount, 0);
    
    // Execute the transaction - it should panic with ArithmeticOverflow.
    let result = test.state.execute::<MockVerifier>(&withdraw_tx);
    
    // Verify that we get the expected arithmetic overflow error.
    match result {
        Err(err) => {
            assert_eq!(err, VAppPanic::ArithmeticOverflow);
        }
        Ok(_) => {
            panic!("Expected ArithmeticOverflow error, but transaction succeeded");
        }
    }
    
    // Verify that the account balance hasn't changed.
    assert_account_balance(&mut test, account, max_balance);
}

#[test]
fn test_withdraw_near_max_no_overflow() {
    let mut test = setup();
    let account = test.requester.address();
    let auctioneer = test.state.auctioneer;
    
    // Set account balance to U256::MAX using deposit.
    let max_balance = U256::MAX;
    let deposit_tx = deposit_tx(account, max_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&mut test, account, max_balance);
    
    // Create a withdrawal that's large but won't overflow when adding the fee.
    // U256::MAX - 2e18 ensures amount + 1e18 fee won't overflow.
    let safe_amount = U256::MAX - U256::from(2e18 as u64);
    let withdraw_tx = withdraw_tx(&test.requester, account, safe_amount, 0);
    
    // Execute the transaction - it should succeed.
    let receipt = test.state.execute::<MockVerifier>(&withdraw_tx).unwrap();
    
    // Verify that the transaction succeeded with correct receipt.
    assert_withdraw_receipt(&receipt, account, safe_amount);
    
    // Verify that the correct amount was deducted (amount + fee).
    let expected_balance = U256::from(2e18 as u64) - U256::from(1e18 as u64); // Max - withdrawn - fee
    let auctioneer_fee = U256::from(1e18 as u64); // 1 PROVE
    assert_account_balance(&mut test, account, expected_balance);
    assert_account_balance(&mut test, auctioneer, auctioneer_fee);
}