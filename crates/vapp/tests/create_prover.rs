mod common;

use alloy_primitives::U256;
use spn_vapp_core::{errors::VAppPanic, verifier::MockVerifier};

use crate::common::*;

#[test]
fn test_create_prover_basic() {
    let mut test = setup();
    let prover_address = test.fulfiller.address();
    let owner_address = test.requester.address();
    let staker_fee_bips = U256::from(500);

    // Execute basic create prover tx.
    let tx = create_prover_tx(prover_address, owner_address, staker_fee_bips, 0, 1, 1);
    let receipt = test.state.execute::<MockVerifier>(&tx).unwrap();

    // Verify the prover account was created correctly.
    assert_prover_account(&mut test, prover_address, owner_address, owner_address, staker_fee_bips);
    assert_create_prover_receipt(&receipt, prover_address, owner_address, staker_fee_bips, 1);
    assert_state_counters(&test, 2, 2, 0, 1);
}

#[test]
fn test_create_prover_self_delegated() {
    let mut test = setup();
    let prover_owner = test.fulfiller.address();
    let staker_fee_bips = U256::from(1000);

    // Execute create prover where owner = prover (self-delegated).
    let tx = create_prover_tx(prover_owner, prover_owner, staker_fee_bips, 0, 1, 1);
    let receipt = test.state.execute::<MockVerifier>(&tx).unwrap();

    // Verify the prover is self-delegated (owner = signer = prover).
    assert_prover_account(&mut test, prover_owner, prover_owner, prover_owner, staker_fee_bips);
    assert_create_prover_receipt(&receipt, prover_owner, prover_owner, staker_fee_bips, 1);
}

#[test]
fn test_create_prover_different_owner() {
    let mut test = setup();
    let prover_address = test.signers[0].address();
    let owner_address = test.signers[1].address();
    let staker_fee_bips = U256::from(250);

    // Execute create prover with different owner and prover addresses.
    let tx = create_prover_tx(prover_address, owner_address, staker_fee_bips, 0, 1, 1);
    let receipt = test.state.execute::<MockVerifier>(&tx).unwrap();

    // Verify the prover account configuration.
    assert_prover_account(&mut test, prover_address, owner_address, owner_address, staker_fee_bips);
    assert_create_prover_receipt(&receipt, prover_address, owner_address, staker_fee_bips, 1);
}

#[test]
fn test_create_prover_various_staker_fees() {
    let mut test = setup();

    // Test with zero staker fee.
    let prover1 = test.signers[0].address();
    let owner1 = test.signers[1].address();
    let tx1 = create_prover_tx(prover1, owner1, U256::ZERO, 0, 1, 1);
    let receipt1 = test.state.execute::<MockVerifier>(&tx1).unwrap();
    assert_prover_account(&mut test, prover1, owner1, owner1, U256::ZERO);
    assert_create_prover_receipt(&receipt1, prover1, owner1, U256::ZERO, 1);

    // Test with 5% staker fee (500 basis points).
    let prover2 = test.signers[2].address();
    let owner2 = test.signers[3].address();
    let staker_fee_500 = U256::from(500);
    let tx2 = create_prover_tx(prover2, owner2, staker_fee_500, 0, 2, 2);
    let receipt2 = test.state.execute::<MockVerifier>(&tx2).unwrap();
    assert_prover_account(&mut test, prover2, owner2, owner2, staker_fee_500);
    assert_create_prover_receipt(&receipt2, prover2, owner2, staker_fee_500, 2);

    // Test with 10% staker fee (1000 basis points).
    let prover3 = test.signers[4].address();
    let owner3 = test.signers[5].address();
    let staker_fee_1000 = U256::from(1000);
    let tx3 = create_prover_tx(prover3, owner3, staker_fee_1000, 1, 1, 3);
    let receipt3 = test.state.execute::<MockVerifier>(&tx3).unwrap();
    assert_prover_account(&mut test, prover3, owner3, owner3, staker_fee_1000);
    assert_create_prover_receipt(&receipt3, prover3, owner3, staker_fee_1000, 3);

    // Test with 50% staker fee (5000 basis points).
    let prover4 = test.signers[6].address();
    let owner4 = test.signers[7].address();
    let staker_fee_5000 = U256::from(5000);
    let tx4 = create_prover_tx(prover4, owner4, staker_fee_5000, 1, 2, 4);
    let receipt4 = test.state.execute::<MockVerifier>(&tx4).unwrap();
    assert_prover_account(&mut test, prover4, owner4, owner4, staker_fee_5000);
    assert_create_prover_receipt(&receipt4, prover4, owner4, staker_fee_5000, 4);

    // Verify state progression.
    assert_state_counters(&test, 5, 5, 1, 2);
}

#[test]
fn test_create_prover_max_staker_fee() {
    let mut test = setup();
    let prover_address = test.fulfiller.address();
    let owner_address = test.requester.address();

    // Test with maximum staker fee (100% = 10000 basis points).
    let max_staker_fee = U256::from(10000);
    let tx = create_prover_tx(prover_address, owner_address, max_staker_fee, 0, 1, 1);
    let receipt = test.state.execute::<MockVerifier>(&tx).unwrap();

    // Verify maximum staker fee is accepted.
    assert_prover_account(&mut test, prover_address, owner_address, owner_address, max_staker_fee);
    assert_create_prover_receipt(&receipt, prover_address, owner_address, max_staker_fee, 1);
}

#[test]
fn test_create_prover_multiple_provers() {
    let mut test = setup();

    // Create multiple provers sequentially.
    let prover1 = test.signers[0].address();
    let owner1 = test.signers[1].address();
    let tx1 = create_prover_tx(prover1, owner1, U256::from(100), 0, 1, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();

    let prover2 = test.signers[2].address();
    let owner2 = test.signers[3].address();
    let tx2 = create_prover_tx(prover2, owner2, U256::from(200), 0, 2, 2);
    test.state.execute::<MockVerifier>(&tx2).unwrap();

    let prover3 = test.signers[4].address();
    let owner3 = test.signers[5].address();
    let tx3 = create_prover_tx(prover3, owner3, U256::from(300), 1, 1, 3);
    test.state.execute::<MockVerifier>(&tx3).unwrap();

    // Verify all provers were created correctly.
    assert_prover_account(&mut test, prover1, owner1, owner1, U256::from(100));
    assert_prover_account(&mut test, prover2, owner2, owner2, U256::from(200));
    assert_prover_account(&mut test, prover3, owner3, owner3, U256::from(300));
    assert_state_counters(&test, 4, 4, 1, 1);
}

#[test]
fn test_create_prover_onchain_tx_out_of_order() {
    let mut test = setup();
    let prover_address = test.fulfiller.address();
    let owner_address = test.requester.address();

    // Execute first create prover.
    let tx1 = create_prover_tx(prover_address, owner_address, U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();

    // Try to execute create prover with wrong onchain_tx (should be 2, but using 4).
    let prover2 = test.signers[0].address();
    let owner2 = test.signers[1].address();
    let tx2 = create_prover_tx(prover2, owner2, U256::from(500), 0, 2, 4);
    let result = test.state.execute::<MockVerifier>(&tx2);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::OnchainTxOutOfOrder { expected: 2, actual: 4 })));

    // Verify state remains unchanged after error.
    assert_prover_account(&mut test, prover_address, owner_address, owner_address, U256::from(500));
    assert_state_counters(&test, 2, 2, 0, 1);
}

#[test]
fn test_create_prover_block_number_regression() {
    let mut test = setup();
    let prover_address = test.fulfiller.address();
    let owner_address = test.requester.address();

    // Execute first create prover at block 15.
    let tx1 = create_prover_tx(prover_address, owner_address, U256::from(500), 15, 1, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();

    // Try to execute create prover at earlier block (regression).
    let prover2 = test.signers[0].address();
    let owner2 = test.signers[1].address();
    let tx2 = create_prover_tx(prover2, owner2, U256::from(500), 10, 1, 2);
    let result = test.state.execute::<MockVerifier>(&tx2);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::BlockNumberOutOfOrder { expected: 15, actual: 10 })));

    // Verify state remains unchanged after error.
    assert_prover_account(&mut test, prover_address, owner_address, owner_address, U256::from(500));
    assert_state_counters(&test, 2, 2, 15, 1);
}

#[test]
fn test_create_prover_log_index_out_of_order() {
    let mut test = setup();
    let prover_address = test.fulfiller.address();
    let owner_address = test.requester.address();

    // Execute first create prover at block 0, log_index 20.
    let tx1 = create_prover_tx(prover_address, owner_address, U256::from(500), 0, 20, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();

    // Try to execute create prover at same block with same log_index.
    let prover2 = test.signers[0].address();
    let owner2 = test.signers[1].address();
    let tx2 = create_prover_tx(prover2, owner2, U256::from(500), 0, 20, 2);
    let result = test.state.execute::<MockVerifier>(&tx2);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::LogIndexOutOfOrder { current: 20, next: 20 })));

    // Try with log_index lower than current.
    let tx3 = create_prover_tx(prover2, owner2, U256::from(500), 0, 15, 2);
    let result = test.state.execute::<MockVerifier>(&tx3);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::LogIndexOutOfOrder { current: 20, next: 15 })));

    // Verify state remains unchanged after error.
    assert_prover_account(&mut test, prover_address, owner_address, owner_address, U256::from(500));
    assert_state_counters(&test, 2, 2, 0, 20);
}

#[test]
fn test_create_prover_log_index_valid_progression() {
    let mut test = setup();
    let prover1 = test.fulfiller.address();
    let owner1 = test.requester.address();

    // Execute first create prover at block 0, log_index 10.
    let tx1 = create_prover_tx(prover1, owner1, U256::from(500), 0, 10, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();

    // Execute second create prover at same block with higher log_index (valid).
    let prover2 = test.signers[0].address();
    let owner2 = test.signers[1].address();
    let tx2 = create_prover_tx(prover2, owner2, U256::from(750), 0, 11, 2);
    let receipt2 = test.state.execute::<MockVerifier>(&tx2).unwrap();

    // Verify both provers and state updates.
    assert_prover_account(&mut test, prover1, owner1, owner1, U256::from(500));
    assert_prover_account(&mut test, prover2, owner2, owner2, U256::from(750));
    assert_create_prover_receipt(&receipt2, prover2, owner2, U256::from(750), 2);
    assert_state_counters(&test, 3, 3, 0, 11);

    // Execute third create prover at higher block (log_index can be anything).
    let prover3 = test.signers[2].address();
    let owner3 = test.signers[3].address();
    let tx3 = create_prover_tx(prover3, owner3, U256::from(1000), 1, 1, 3);
    let receipt3 = test.state.execute::<MockVerifier>(&tx3).unwrap();

    // Verify final state after block progression.
    assert_prover_account(&mut test, prover3, owner3, owner3, U256::from(1000));
    assert_create_prover_receipt(&receipt3, prover3, owner3, U256::from(1000), 3);
    assert_state_counters(&test, 4, 4, 1, 1);
}
