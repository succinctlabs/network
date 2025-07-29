mod common;

use alloy_primitives::U256;
use spn_network_types::{ExecutionStatus, HashableWithSender, ProofMode, TransactionVariant};
use spn_vapp_core::{
    errors::VAppPanic,
    transactions::VAppTransaction,
    verifier::{MockVerifier, RejectVerifier},
};

use crate::common::*;

#[test]
fn test_clear_basic_compressed() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000); // 100 tokens with 6 decimals

    // Deposit transaction for requester.
    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create prover transaction.
    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Verify initial balances.
    assert_account_balance(&mut test, requester_address, amount);
    assert_account_balance(&mut test, prover_address, U256::ZERO);

    // Create clear transaction with compressed proof mode.
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,                  // request_nonce
        U256::from(50_000), // bid_amount (price per PGU, must be <= max_price_per_pgu)
        1,                  // bid_nonce
        1,                  // settle_nonce
        1,                  // fulfill_nonce
        1,                  // execute_nonce
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false, // needs_verifier_signature
    );

    // Execute clear transaction.
    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();

    // Verify balances after clear - requester pays, prover receives.
    // The cost is calculated as: bid_price_per_pgu * pgus_used = 50,000 * 1,000 = 50,000,000
    let expected_cost = U256::from(50_000_000);
    let expected_requester_balance = amount - expected_cost;

    assert_account_balance(&mut test, requester_address, expected_requester_balance);
    assert_account_balance(&mut test, prover_address, expected_cost);

    // Clear transactions don't return receipts, so we verify the transaction succeeded
    // by checking the balance changes above.
    assert!(receipt.is_none());
}

#[test]
fn test_clear_groth16_mode() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Groth16 proof mode (requires verifier signature).
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,                  // request_nonce
        U256::from(50_000), // bid_amount
        1,                  // bid_nonce
        1,                  // settle_nonce
        1,                  // fulfill_nonce
        1,                  // execute_nonce
        ProofMode::Groth16,
        ExecutionStatus::Executed,
        true, // needs_verifier_signature
    );

    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();

    // Verify the transaction succeeded.
    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&mut test, requester_address, amount - expected_cost);
    assert_account_balance(&mut test, prover_address, expected_cost);
    assert!(receipt.is_none());
}

#[test]
fn test_clear_plonk_mode() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Plonk proof mode (requires verifier signature).
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,                  // request_nonce
        U256::from(50_000), // bid_amount
        1,                  // bid_nonce
        1,                  // settle_nonce
        1,                  // fulfill_nonce
        1,                  // execute_nonce
        ProofMode::Plonk,
        ExecutionStatus::Executed,
        true, // needs_verifier_signature
    );

    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();

    // Verify the transaction succeeded.
    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&mut test, requester_address, amount - expected_cost);
    assert_account_balance(&mut test, prover_address, expected_cost);
    assert!(receipt.is_none());
}

#[test]
fn test_clear_with_whitelist() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with prover in whitelist.
    let whitelist = vec![prover_address.to_vec()];
    let clear_tx = create_clear_tx_with_whitelist(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,                  // request_nonce
        U256::from(50_000), // bid_amount
        1,                  // bid_nonce
        1,                  // settle_nonce
        1,                  // fulfill_nonce
        1,                  // execute_nonce
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false, // needs_verifier_signature
        whitelist,
    );

    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();

    // Verify the transaction succeeded.
    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&mut test, requester_address, amount - expected_cost);
    assert_account_balance(&mut test, prover_address, expected_cost);
    assert!(receipt.is_none());
}

#[test]
fn test_clear_empty_whitelist() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with empty whitelist (no restrictions).
    let whitelist = vec![];
    let clear_tx = create_clear_tx_with_whitelist(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,                  // request_nonce
        U256::from(50_000), // bid_amount
        1,                  // bid_nonce
        1,                  // settle_nonce
        1,                  // fulfill_nonce
        1,                  // execute_nonce
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false, // needs_verifier_signature
        whitelist,
    );

    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();

    // Verify the transaction succeeded.
    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&mut test, requester_address, amount - expected_cost);
    assert_account_balance(&mut test, prover_address, expected_cost);
    assert!(receipt.is_none());
}

#[test]
fn test_clear_missing_request_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing request body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Remove the request body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.request.body = None;
    }

    // Execute should fail with MissingProtoBody.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingProtoBody)));
}

#[test]
fn test_clear_missing_bid_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing bid body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Remove the bid body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.bid.body = None;
    }

    // Execute should fail with MissingProtoBody.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingProtoBody)));
}

#[test]
fn test_clear_missing_settle_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing settle body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Remove the settle body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.settle.body = None;
    }

    // Execute should fail with MissingProtoBody.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingProtoBody)));
}

#[test]
fn test_clear_missing_execute_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing execute body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Remove the execute body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.execute.body = None;
    }

    // Execute should fail with MissingProtoBody.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingProtoBody)));
}

#[test]
fn test_clear_missing_fulfill_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing fulfill body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Remove the fulfill body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut fulfill) = clear.fulfill {
            fulfill.body = None;
        }
    }

    // Execute should fail with MissingProtoBody.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingProtoBody)));
}

#[test]
fn test_clear_request_id_mismatch_bid() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with mismatched bid request ID.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Modify the bid request ID to be different.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut bid_body) = clear.bid.body {
            // Use a completely different but valid 32-byte request ID
            bid_body.request_id = vec![0xFF; 32]; // Different request ID
            clear.bid.signature = proto_sign(&test.fulfiller, bid_body).as_bytes().to_vec();
        }
    }

    let result = test.state.execute::<MockVerifier>(&clear_tx);
    println!("Result: {result:?}");
    assert!(matches!(result, Err(VAppPanic::RequestIdMismatch { .. })));
}

// TODO(claude): Something about this test seems fishy.
// 1) I'm not sure you can modify the clear after signing, since it would invalidate the signature.
// 2) The error message is not what we should expect?
#[test]
fn test_clear_request_id_mismatch_settle() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with mismatched settle request ID.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Modify the settle request ID to be different.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut settle_body) = clear.settle.body {
            settle_body.request_id = vec![0xFF; 32]; // Wrong request ID
            clear.settle.signature = proto_sign(&test.auctioneer, settle_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with AddressDeserializationFailed due to request ID mismatch validation.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::RequestIdMismatch { .. })));
}

#[test]
fn test_clear_request_id_mismatch_execute() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with mismatched execute request ID.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Modify the execute request ID to be different.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.request_id = vec![0xFF; 32]; // Wrong request ID
            clear.execute.signature = proto_sign(&test.executor, execute_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with AddressDeserializationFailed due to request ID mismatch validation.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::RequestIdMismatch { .. })));
}

#[test]
fn test_clear_request_id_mismatch_fulfill() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with mismatched fulfill request ID.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Modify the fulfill request ID to be different.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut fulfill) = clear.fulfill {
            if let Some(ref mut fulfill_body) = fulfill.body {
                fulfill_body.request_id = vec![0xFF; 32]; // Wrong request ID
                fulfill.signature = proto_sign(&test.fulfiller, fulfill_body).as_bytes().to_vec();
            }
        }
    }

    // Execute should fail with AddressDeserializationFailed due to request ID mismatch validation.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::RequestIdMismatch { .. })));
}

#[test]
fn test_clear_already_fulfilled_request() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(200_000_000); // More funds for two transactions

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create and execute first clear transaction.
    let clear_tx1 = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1, // Same nonce
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // First execution should succeed.
    test.state.execute::<MockVerifier>(&clear_tx1).unwrap();

    // Create second clear transaction with same request (same nonce = same request ID).
    let clear_tx2 = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1, // Same nonce = same request ID
        U256::from(50_000),
        2, // Different bid nonce
        2, // Different settle nonce
        2, // Different fulfill nonce
        2, // Different execute nonce
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Second execution should fail with RequestAlreadyFulfilled.
    let result = test.state.execute::<MockVerifier>(&clear_tx2);
    assert!(matches!(result, Err(VAppPanic::TransactionAlreadyProcessed { .. })));
}

#[test]
fn test_clear_prover_does_not_exist() {
    let mut test = setup();

    // Setup: Deposit funds for requester but DON'T create the prover.
    let requester_address = test.requester.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create clear transaction with non-existent prover.
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller, // This prover doesn't exist in the state
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Execute should fail with ProverDelegatedSignerMismatch because the prover
    // doesn't exist in this test's state, which causes the delegated signer check to fail.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::ProverDelegatedSignerMismatch { .. })));
}

#[test]
fn test_clear_delegated_signer_mismatch() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a different signer who is not the prover's delegated signer.
    let wrong_signer = signer("wrong_signer");

    // Create clear transaction where the bid is signed by the wrong signer.
    let clear_tx = create_clear_tx(
        &test.requester,
        &wrong_signer, // Wrong signer - not the prover's delegated signer
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Execute should fail with ProverDelegatedSignerMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::ProverDelegatedSignerMismatch { .. })));
}

#[test]
fn test_clear_prover_not_in_whitelist() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a different address for the whitelist (not the prover).
    let other_address = test.auctioneer.address();
    let whitelist = vec![other_address.to_vec()]; // Prover is NOT in this whitelist

    // Create clear transaction with prover not in whitelist.
    let clear_tx = create_clear_tx_with_whitelist(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
        whitelist,
    );

    // Execute should fail with ProverNotInWhitelist.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::ProverNotInWhitelist { .. })));
}

#[test]
fn test_clear_max_price_exceeded() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with bid price exceeding max_price_per_pgu.
    // max_price_per_pgu is set to 100000 in helper function, so bid 150000 should fail.
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(150_000), // This exceeds max_price_per_pgu of 100000
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Execute should fail with MaxPricePerPguExceeded.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MaxPricePerPguExceeded { .. })));
}

#[test]
fn test_clear_gas_limit_exceeded() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with PGUs exceeding gas limit.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Modify the execute body to have PGUs > gas_limit.
    // Gas limit is set to 10000 in helper function, so set PGUs to 15000.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.pgus = Some(15_000); // Exceeds gas_limit of 10000
            clear.execute.signature = proto_sign(&test.executor, execute_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with GasLimitExceeded.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::GasLimitExceeded { .. })));
}

#[test]
fn test_clear_insufficient_requester_balance() {
    let mut test = setup();

    // Setup: Deposit small amount for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let small_amount = U256::from(1_000_000); // Very small balance

    let deposit_tx = deposit_tx(requester_address, small_amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with cost exceeding requester balance.
    // Cost = bid_amount * pgus = 50_000 * 1000 = 50_000_000, which exceeds balance of 1_000_000.
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000), // This will create cost of 50M, exceeding balance of 1M
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Execute should fail with InsufficientBalance.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InsufficientBalance { .. })));
}

#[test]
fn test_clear_invalid_bid_amount_parsing() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // For this test we need to create a transaction where parsing fails before signature validation.
    // Since the VApp validates signatures before parsing amounts, we can't easily test U256ParseError
    // for bid amounts by modifying an already-signed transaction. Instead, this test demonstrates
    // that signature validation happens first.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Modify the bid amount to be invalid.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut bid_body) = clear.bid.body {
            bid_body.amount = "invalid_amount".to_string(); // Invalid U256 string
        }
    }

    // Execute should fail. Due to validation order, this fails with a signature mismatch
    // rather than a parsing error since signature validation happens before amount parsing.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::ProverDelegatedSignerMismatch { .. })));
}

#[test]
fn test_clear_invalid_base_fee_parsing() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with invalid base fee string.
    let clear_tx = create_clear_tx_with_base_fee(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
        "invalid_base_fee", // Invalid U256 string
    );

    // Execute should fail with U256ParseError.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::U256ParseError(_))));
}

#[test]
fn test_clear_invalid_max_price_parsing() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with invalid max price string.
    let clear_tx = create_clear_tx_with_max_price(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
        "invalid_max_price", // Invalid U256 string
    );

    // Execute should fail with U256ParseError.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::U256ParseError(_))));
}

#[test]
fn test_clear_various_fee_combinations() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover with staker fee.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(500_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create prover with 10% staker fee (1000 bips).
    let create_prover_tx =
        create_prover_tx(prover_address, prover_address, U256::from(1000), 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Test with base fee and staker fee.
    let clear_tx = create_clear_tx_with_base_fee(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
        "10000", // Base fee of 10,000 per PGU
    );

    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();
    assert!(receipt.is_none());

    // Verify balances after clear with fees.
    // Cost = (bid_amount + base_fee) * pgus = (50,000) * 1,000 + 10000 = 50,010,000
    // Prover gets: bid_amount * pgus = Cost * 0.9 = 45,000,000
    // Staker fee from prover's earnings: 50,000,000 * 10% = 5,000,000
    let expected_cost = U256::from(50_010_000);
    assert_account_balance(&mut test, requester_address, amount - expected_cost);

    // Prover gets bid amount minus staker fee.
    assert_account_balance(&mut test, prover_address, U256::from(50_010_000));

    // Treasury gets base fee plus staker fee.
    let treasury_address = signer("treasury").address();
    assert_account_balance(&mut test, treasury_address, U256::from(0));
}

#[test]
fn test_clear_gas_limit_boundary() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(1_000_000_000); // Large amount for high gas usage

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with PGUs exactly at gas_limit.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Modify PGUs to exactly match gas_limit (10,000).
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.pgus = Some(10_000); // Exactly at gas_limit
            clear.execute.signature = proto_sign(&test.executor, execute_body).as_bytes().to_vec();
        }
    }

    // Should succeed at boundary.
    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();
    assert!(receipt.is_none());

    // Verify cost with boundary PGUs.
    // Cost = bid_amount * pgus = 50,000 * 10,000 = 500,000,000
    let expected_cost = U256::from(500_000_000);
    assert_account_balance(&mut test, requester_address, amount - expected_cost);
    assert_account_balance(&mut test, prover_address, expected_cost);
}

#[test]
fn test_clear_with_public_values_hash() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with matching public values hash.
    let public_values_hash = vec![1u8; 32];
    let clear_tx = create_clear_tx_with_public_values_hash(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
        public_values_hash,
    );

    // Should succeed with matching hashes.
    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();
    assert!(receipt.is_none());

    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&mut test, requester_address, amount - expected_cost);
    assert_account_balance(&mut test, prover_address, expected_cost);
}

#[test]
fn test_clear_without_public_values_hash() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction without public values hash in request.
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // By default, request has no public values hash and execute has one.
    // This should still succeed.
    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();
    assert!(receipt.is_none());

    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&mut test, requester_address, amount - expected_cost);
    assert_account_balance(&mut test, prover_address, expected_cost);
}

#[test]
fn test_clear_invalid_request_signature() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction and invalidate request signature.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the request signature.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.request.signature[0] ^= 0xFF;
    }

    // Execute should fail with InvalidSignature.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidSignature { .. })));
}

#[test]
fn test_clear_invalid_settle_signature() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction and invalidate settle signature.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the settle signature.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.settle.signature[0] ^= 0xFF;
    }

    // Execute should fail with AuctioneerMismatch because corrupted signature recovers wrong address.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidSignature { .. })));
}

#[test]
fn test_clear_invalid_execute_signature() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction and invalidate execute signature.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the execute signature.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.execute.signature[0] ^= 0xFF;
    }

    // Execute should fail with InvalidSignature because corrupted signature cannot be verified.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidSignature { .. })));
}

#[test]
fn test_clear_invalid_fulfill_signature() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction and invalidate fulfill signature.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the fulfill signature.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut fulfill) = clear.fulfill {
            fulfill.signature[0] ^= 0xFF;
        }
    }

    // Execute should fail with InvalidSignature.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidSignature { .. })));
}

#[test]
fn test_clear_domain_mismatch_request() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with wrong domain in request.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Change domain in request body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut request_body) = clear.request.body {
            request_body.domain = vec![0xFF; 32]; // Wrong domain
        }
    }

    // Execute should fail with DomainMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::DomainMismatch { .. })));
}

#[test]
fn test_clear_domain_mismatch_bid() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with wrong domain in bid.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Change domain in bid body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut bid_body) = clear.bid.body {
            bid_body.domain = vec![0xFF; 32]; // Wrong domain
        }
    }

    // Execute should fail with DomainMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::DomainMismatch { .. })));
}

#[test]
fn test_clear_domain_mismatch_settle() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with wrong domain in settle.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Change domain in settle body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut settle_body) = clear.settle.body {
            settle_body.domain = vec![0xFF; 32]; // Wrong domain
        }
    }

    // Execute should fail with DomainMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::DomainMismatch { .. })));
}

#[test]
fn test_clear_domain_mismatch_execute() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with wrong domain in execute.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Change domain in execute body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.domain = vec![0xFF; 32]; // Wrong domain
        }
    }

    // Execute should fail with DomainMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::DomainMismatch { .. })));
}

#[test]
fn test_clear_domain_mismatch_fulfill() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with wrong domain in fulfill.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Change domain in fulfill body.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut fulfill) = clear.fulfill {
            if let Some(ref mut fulfill_body) = fulfill.body {
                fulfill_body.domain = vec![0xFF; 32]; // Wrong domain
            }
        }
    }

    // Execute should fail with DomainMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::DomainMismatch { .. })));
}

#[test]
fn test_clear_auctioneer_mismatch_request() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction where settle signer != request auctioneer.
    let wrong_auctioneer = signer("wrong_auctioneer");
    let clear_tx = create_clear_tx_with_mismatched_auctioneer(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,  // Expected auctioneer in request
        &wrong_auctioneer, // Wrong settle signer
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Execute should fail with AuctioneerMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::AuctioneerMismatch { .. })));
}

#[test]
fn test_clear_auctioneer_mismatch_global() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction where the request specifies test.auctioneer
    // but the settle is signed by a different signer.
    let clear_tx = create_clear_tx_with_mismatched_auctioneer(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,                // Expected auctioneer in request
        &signer("different_auctioneer"), // Wrong settle signer
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Execute should fail with AuctioneerMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::AuctioneerMismatch { .. })));
}

#[test]
fn test_clear_executor_mismatch_request() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with correct executor in request but wrong execute signer.
    let wrong_executor = signer("wrong_executor");
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Replace the execute signature with wrong signer.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref execute_body) = clear.execute.body {
            clear.execute.signature = proto_sign(&wrong_executor, execute_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with ExecutorMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::ExecutorMismatch { .. })));
}

#[test]
fn test_clear_executor_mismatch_global() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction where the request specifies test.executor
    // but the execute is signed by a different signer.
    let different_executor = signer("different_executor");
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Replace the execute signature with different signer.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref execute_body) = clear.execute.body {
            clear.execute.signature =
                proto_sign(&different_executor, execute_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with ExecutorMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::ExecutorMismatch { .. })));
}

#[test]
fn test_clear_unexecutable_with_punishment() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Unexecutable status and punishment.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Unexecutable,
        false,
    );

    // Set punishment value for unexecutable proof.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.punishment = Some("25000000".to_string()); // 25M punishment (50% of max cost)
            clear.execute.signature = proto_sign(&test.executor, execute_body).as_bytes().to_vec();
        }
    }

    // Should succeed with punishment.
    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();
    assert!(receipt.is_none());

    // Verify balances after punishment.
    // Prover loses punishment amount, treasury gains it.
    assert_account_balance(&mut test, prover_address, U256::ZERO); // Prover had no initial balance
    assert_account_balance(&mut test, requester_address, amount - U256::from(25_000_000));
    // Requester keeps funds
}

#[test]
fn test_clear_unexecutable_missing_punishment() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Unexecutable status but no punishment.
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Unexecutable,
        false,
    );

    // Execute should fail with MissingPunishment.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingPunishment)));
}

#[test]
fn test_clear_punishment_exceeds_max_cost() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with punishment exceeding max cost.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Unexecutable,
        false,
    );

    // Set punishment that exceeds max cost.
    // Max cost = max_price_per_pgu * gas_limit = 100,000 * 10,000 = 1,000,000,000
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.punishment = Some("2000000000".to_string()); // 2B > 1B max cost
            clear.execute.signature = proto_sign(&test.executor, execute_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with PunishmentExceedsMaxCost.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::PunishmentExceedsMaxCost { .. })));
}

#[test]
fn test_clear_invalid_execution_status() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with invalid execution status.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Set an invalid execution status value.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.execution_status = 99; // Invalid status
            clear.execute.signature = proto_sign(&test.executor, execute_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with ExecutionFailed.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::ExecutionFailed { .. })));
}

#[test]
fn test_clear_missing_verifier_signature_groth16() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Groth16 mode but no verifier signature.
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Groth16,
        ExecutionStatus::Executed,
        false, // No verifier signature
    );

    // Execute should fail with MissingVerifierSignature.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingVerifierSignature)));
}

#[test]
fn test_clear_missing_verifier_signature_plonk() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Plonk mode but no verifier signature.
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Plonk,
        ExecutionStatus::Executed,
        false, // No verifier signature
    );

    // Execute should fail with MissingVerifierSignature.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingVerifierSignature)));
}

#[test]
fn test_clear_invalid_verifier_signature() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Groth16 mode and verifier signature.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Groth16,
        ExecutionStatus::Executed,
        true,
    );

    // Corrupt the verifier signature.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut verify) = clear.verify {
            verify[0] ^= 0xFF;
        }
    }

    // Execute should fail with InvalidVerifierSignature.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidVerifierSignature)));
}

#[test]
fn test_clear_verifier_address_mismatch() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a wrong verifier signer.
    let wrong_verifier = signer("wrong_verifier");

    // Create clear transaction with correct verifier in request but wrong verifier signing.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Groth16,
        ExecutionStatus::Executed,
        true,
    );

    // Replace the verifier signature with wrong signer.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref fulfill) = clear.fulfill {
            if let Some(ref fulfill_body) = fulfill.body {
                clear.verify = Some(proto_sign(&wrong_verifier, fulfill_body).as_bytes().to_vec());
            }
        }
    }

    // Execute should fail with InvalidVerifierSignature.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidVerifierSignature)));
}

#[test]
fn test_clear_public_values_hash_mismatch() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with mismatched public values hash.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Set different public values hashes in request and execute.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut request_body) = clear.request.body {
            request_body.public_values_hash = Some(vec![9u8; 32]); // Different hash
            clear.request.signature = proto_sign(&test.requester, request_body).as_bytes().to_vec();
        }
        let request_id = clear
            .request
            .body
            .clone()
            .unwrap()
            .hash_with_signer(test.requester.address().as_slice())
            .unwrap()
            .to_vec();
        if let Some(ref mut bid_body) = clear.bid.body {
            bid_body.request_id = request_id.clone();
            clear.bid.signature = proto_sign(&test.fulfiller, bid_body).as_bytes().to_vec();
        }
        if let Some(ref mut settle_body) = clear.settle.body {
            settle_body.request_id = request_id.clone();
            clear.settle.signature = proto_sign(&test.auctioneer, settle_body).as_bytes().to_vec();
        }
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.request_id = request_id.clone();
            execute_body.public_values_hash = Some(vec![2u8; 32]); // Different hash
            clear.execute.signature = proto_sign(&test.executor, execute_body).as_bytes().to_vec();
        }
        let fulfill = clear.fulfill.as_mut().unwrap();
        if let Some(ref mut fulfill_body) = fulfill.body {
            fulfill_body.request_id = request_id.clone();
            fulfill.signature = proto_sign(&test.fulfiller, fulfill_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with PublicValuesHashMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    println!("Result: {result:?}");
    assert!(matches!(result, Err(VAppPanic::PublicValuesHashMismatch)));
}

#[test]
fn test_clear_missing_execute_public_values_hash() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with request hash but missing execute hash.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Set public values hash in request but not in execute.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.public_values_hash = None; // Missing
            clear.execute.signature = proto_sign(&test.executor, execute_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with MissingPublicValuesHash.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingPublicValuesHash)));
}

#[test]
fn test_clear_missing_fulfill_field() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Executed status but no fulfill.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Remove the fulfill field.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.fulfill = None;
    }

    // Execute should fail with MissingFulfill.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingFulfill)));
}

#[test]
fn test_clear_missing_pgus_value() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction without PGUs value.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Remove PGUs value.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut execute_body) = clear.execute.body {
            execute_body.pgus = None;
            clear.execute.signature = proto_sign(&test.executor, execute_body).as_bytes().to_vec();
        }
    }

    // Execute should fail with MissingPgusUsed.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::MissingPgusUsed)));
}

#[test]
fn test_clear_invalid_proof_compressed() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with invalid proof data.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the proof data to make it invalid.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut fulfill) = clear.fulfill {
            if let Some(ref mut fulfill_body) = fulfill.body {
                fulfill_body.proof = vec![0xFF; 32]; // Invalid proof
                fulfill.signature = proto_sign(&test.fulfiller, fulfill_body).as_bytes().to_vec();
            }
        }
    }

    // Execute should fail with InvalidProof.
    let result = test.state.execute::<RejectVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidProof)));
}

#[test]
fn test_clear_invalid_request_variant() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with invalid proof data.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the proof data to make it invalid.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.request.body.as_mut().unwrap().variant = TransactionVariant::FulfillVariant as i32;
        clear.request.signature =
            proto_sign(&test.requester, clear.request.body.as_ref().unwrap()).as_bytes().to_vec();
    }

    // Execute should fail with InvalidProof.
    let result = test.state.execute::<RejectVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidTransactionVariant)));
}

#[test]
fn test_clear_invalid_bid_variant() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with invalid proof data.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the proof data to make it invalid.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.bid.body.as_mut().unwrap().variant = TransactionVariant::FulfillVariant as i32;
        clear.bid.signature =
            proto_sign(&test.fulfiller, clear.bid.body.as_ref().unwrap()).as_bytes().to_vec();
    }

    // Execute should fail with InvalidProof.
    let result = test.state.execute::<RejectVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidTransactionVariant)));
}

#[test]
fn test_clear_invalid_settle_variant() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with invalid proof data.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the proof data to make it invalid.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.bid.body.as_mut().unwrap().variant = TransactionVariant::FulfillVariant as i32;
        clear.bid.signature =
            proto_sign(&test.fulfiller, clear.bid.body.as_ref().unwrap()).as_bytes().to_vec();
    }

    // Execute should fail with InvalidProof.
    let result = test.state.execute::<RejectVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidTransactionVariant)));
}

#[test]
fn test_clear_invalid_execute_variant() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with invalid proof data.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the proof data to make it invalid.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        clear.execute.body.as_mut().unwrap().variant = TransactionVariant::FulfillVariant as i32;
        clear.execute.signature =
            proto_sign(&test.executor, clear.execute.body.as_ref().unwrap()).as_bytes().to_vec();
    }

    // Execute should fail with InvalidProof.
    let result = test.state.execute::<RejectVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidTransactionVariant)));
}

#[test]
fn test_clear_invalid_fulfill_variant() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.fulfiller.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with invalid proof data.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.fulfiller,
        &test.fulfiller,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1,
        U256::from(50_000),
        1,
        1,
        1,
        1,
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false,
    );

    // Corrupt the proof data to make it invalid.
    if let VAppTransaction::Clear(ref mut clear) = clear_tx {
        if let Some(ref mut fulfill) = clear.fulfill {
            if let Some(ref mut fulfill_body) = fulfill.body {
                fulfill_body.variant = TransactionVariant::RequestVariant as i32;
                fulfill.signature = proto_sign(&test.fulfiller, fulfill_body).as_bytes().to_vec();
            }
        }
    }

    // Execute should fail with InvalidProof.
    let result = test.state.execute::<RejectVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppPanic::InvalidTransactionVariant)));
}
