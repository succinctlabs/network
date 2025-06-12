
mod common;

use alloy_primitives::U256;
use spn_network_types::{ExecutionStatus, ProofMode};
use spn_vapp_core::{
    errors::{VAppError, VAppPanic},
    transactions::VAppTransaction,
    verifier::MockVerifier,
};

use crate::common::*;

#[test]
fn test_clear_basic_compressed() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000); // 100 tokens with 6 decimals

    // Deposit transaction for requester.
    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create prover transaction.
    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Verify initial balances.
    assert_account_balance(&test, requester_address, amount);
    assert_account_balance(&test, prover_address, U256::ZERO);

    // Create clear transaction with compressed proof mode.
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1, // request_nonce
        U256::from(50_000), // bid_amount (price per PGU, must be <= max_price_per_pgu)
        1, // bid_nonce
        1, // settle_nonce
        1, // fulfill_nonce
        1, // execute_nonce
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
    
    assert_account_balance(&test, requester_address, expected_requester_balance);
    assert_account_balance(&test, prover_address, expected_cost);

    // Clear transactions don't return receipts, so we verify the transaction succeeded
    // by checking the balance changes above.
    assert!(receipt.is_none());
}

#[test]
fn test_clear_groth16_mode() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Groth16 proof mode (requires verifier signature).
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1, // request_nonce
        U256::from(50_000), // bid_amount
        1, // bid_nonce
        1, // settle_nonce
        1, // fulfill_nonce
        1, // execute_nonce
        ProofMode::Groth16,
        ExecutionStatus::Executed,
        true, // needs_verifier_signature
    );

    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();

    // Verify the transaction succeeded.
    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&test, requester_address, amount - expected_cost);
    assert_account_balance(&test, prover_address, expected_cost);
    assert!(receipt.is_none());
}

#[test]
fn test_clear_plonk_mode() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with Plonk proof mode (requires verifier signature).
    let clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1, // request_nonce
        U256::from(50_000), // bid_amount
        1, // bid_nonce
        1, // settle_nonce
        1, // fulfill_nonce
        1, // execute_nonce
        ProofMode::Plonk,
        ExecutionStatus::Executed,
        true, // needs_verifier_signature
    );

    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();

    // Verify the transaction succeeded.
    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&test, requester_address, amount - expected_cost);
    assert_account_balance(&test, prover_address, expected_cost);
    assert!(receipt.is_none());
}

#[test]
fn test_clear_with_whitelist() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with prover in whitelist.
    let whitelist = vec![prover_address.to_vec()];
    let clear_tx = create_clear_tx_with_whitelist(
        &test.requester,
        &test.prover,
        &test.prover,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1, // request_nonce
        U256::from(50_000), // bid_amount
        1, // bid_nonce
        1, // settle_nonce
        1, // fulfill_nonce
        1, // execute_nonce
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false, // needs_verifier_signature
        whitelist,
    );

    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();

    // Verify the transaction succeeded.
    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&test, requester_address, amount - expected_cost);
    assert_account_balance(&test, prover_address, expected_cost);
    assert!(receipt.is_none());
}

#[test]
fn test_clear_empty_whitelist() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create clear transaction with empty whitelist (no restrictions).
    let whitelist = vec![];
    let clear_tx = create_clear_tx_with_whitelist(
        &test.requester,
        &test.prover,
        &test.prover,
        &test.auctioneer,
        &test.executor,
        &test.verifier,
        1, // request_nonce
        U256::from(50_000), // bid_amount
        1, // bid_nonce
        1, // settle_nonce
        1, // fulfill_nonce
        1, // execute_nonce
        ProofMode::Compressed,
        ExecutionStatus::Executed,
        false, // needs_verifier_signature
        whitelist,
    );

    let receipt = test.state.execute::<MockVerifier>(&clear_tx).unwrap();

    // Verify the transaction succeeded.
    let expected_cost = U256::from(50_000_000);
    assert_account_balance(&test, requester_address, amount - expected_cost);
    assert_account_balance(&test, prover_address, expected_cost);
    assert!(receipt.is_none());
}

#[test]
fn test_clear_missing_request_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing request body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::MissingProtoBody))));
}

#[test]
fn test_clear_missing_bid_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing bid body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::MissingProtoBody))));
}

#[test]
fn test_clear_missing_settle_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing settle body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::MissingProtoBody))));
}

#[test]
fn test_clear_missing_execute_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing execute body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::MissingProtoBody))));
}

#[test]
fn test_clear_missing_fulfill_body() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with missing fulfill body.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::MissingProtoBody))));
}

#[test]
fn test_clear_request_id_mismatch_bid() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with mismatched bid request ID.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
            bid_body.request_id = vec![1; 32]; // Wrong request ID
        }
    }

    // Execute should fail with RequestIdMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    println!("Actual result: {:?}", result);
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::RequestIdMismatch { .. }))));
}

#[test]
fn test_clear_request_id_mismatch_settle() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with mismatched settle request ID.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
            settle_body.request_id = vec![2; 32]; // Wrong request ID
        }
    }

    // Execute should fail with RequestIdMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::RequestIdMismatch { .. }))));
}

#[test]
fn test_clear_request_id_mismatch_execute() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with mismatched execute request ID.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
            execute_body.request_id = vec![3; 32]; // Wrong request ID
        }
    }

    // Execute should fail with RequestIdMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::RequestIdMismatch { .. }))));
}

#[test]
fn test_clear_request_id_mismatch_fulfill() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(100_000_000);

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create a clear transaction with mismatched fulfill request ID.
    let mut clear_tx = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
                fulfill_body.request_id = vec![4; 32]; // Wrong request ID
            }
        }
    }

    // Execute should fail with RequestIdMismatch.
    let result = test.state.execute::<MockVerifier>(&clear_tx);
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::RequestIdMismatch { .. }))));
}

#[test]
fn test_clear_already_fulfilled_request() {
    let mut test = setup();

    // Setup: Deposit funds for requester and create prover.
    let requester_address = test.requester.address();
    let prover_address = test.prover.address();
    let amount = U256::from(200_000_000); // More funds for two transactions

    let deposit_tx = deposit_tx(requester_address, amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    let create_prover_tx = create_prover_tx(prover_address, prover_address, U256::ZERO, 1, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create and execute first clear transaction.
    let clear_tx1 = create_clear_tx(
        &test.requester,
        &test.prover,
        &test.prover,
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
        &test.prover,
        &test.prover,
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
    assert!(matches!(result, Err(VAppError::Panic(VAppPanic::RequestAlreadyFulfilled { .. }))));
}

// #[test]
// fn test_clear() {
//     let mut test = setup();

//     // Local signers for this test.
//     let requester_signer = &test.requester;
//     let bidder_signer = &test.prover;
//     let fulfiller_signer = &test.prover;
//     let settle_signer = &test.auctioneer;
//     let executor_signer = &test.executor;
//     let verifier_signer = &test.verifier;

//     // Deposit tx
//     let tx = VAppTransaction::Deposit(OnchainTransaction {
//         tx_hash: None,
//         block: 0,
//         log_index: 1,
//         onchain_tx: 1,
//         action: Deposit { account: requester_signer.address(), amount: U256::from(100e6) },
//     });
//     test.state.execute::<MockVerifier>(&tx).unwrap();

//     // Set up prover with delegated signer.
//     let prover_tx = VAppTransaction::CreateProver(OnchainTransaction {
//         tx_hash: None,
//         block: 1,
//         log_index: 2,
//         onchain_tx: 2,
//         action: CreateProver {
//             prover: bidder_signer.address(),
//             owner: bidder_signer.address(), // Self-delegated
//             stakerFeeBips: U256::from(0),
//         },
//     });
//     test.state.execute::<MockVerifier>(&prover_tx).unwrap();

//     let account_address: Address = requester_signer.address();
//     assert_eq!(test.state.accounts.get(&account_address).unwrap().get_balance(), U256::from(100e6),);

//     let request_body = RequestProofRequestBody {
//         nonce: 1,
//         vk_hash: hex::decode("005b97bb81b9ed64f9321049013a56d9633c115b076ae4144f2622d0da13d683")
//             .unwrap(),
//         version: "sp1-v3.0.0".to_string(),
//         mode: spn_network_types::ProofMode::Groth16 as i32,
//         strategy: FulfillmentStrategy::Auction.into(),
//         stdin_uri: "s3://spn-artifacts-production3/stdins/artifact_01jqcgtjr7es883amkx30sqkg9"
//             .to_string(),
//         deadline: 1000,
//         cycle_limit: 1000,
//         gas_limit: 10000,
//         min_auction_period: 0,
//         whitelist: vec![],
//         domain: SPN_SEPOLIA_V1_DOMAIN.to_vec(),
//         auctioneer: test.auctioneer.address().to_vec(),
//         executor: test.executor.address().to_vec(),
//         verifier: test.verifier.address().to_vec(),
//         public_values_hash: None,
//         base_fee: "0".to_string(),
//         max_price_per_pgu: "1000000000000000000".to_string(),
//     };
//     let proof = vec![
//         17, 182, 160, 157, 40, 242, 129, 34, 129, 204, 131, 191, 247, 169, 187, 69, 119, 90, 227,
//         82, 88, 207, 116, 44, 34, 113, 109, 48, 85, 75, 45, 95, 111, 205, 161, 129, 18, 175, 110,
//         238, 88, 46, 229, 251, 208, 212, 65, 200, 159, 144, 27, 252, 203, 116, 11, 243, 245, 60,
//         193, 115, 19, 186, 8, 52, 108, 195, 11, 30, 31, 12, 176, 52, 162, 22, 135, 115, 165, 161,
//         191, 161, 111, 60, 246, 104, 207, 32, 178, 36, 15, 23, 97, 222, 253, 16, 81, 231, 255, 67,
//         0, 59, 15, 140, 83, 36, 88, 90, 163, 253, 245, 233, 211, 239, 210, 154, 16, 4, 68, 40, 3,
//         4, 146, 9, 82, 199, 52, 237, 208, 4, 31, 61, 16, 233, 26, 211, 199, 211, 213, 71, 232, 95,
//         36, 28, 213, 124, 207, 120, 62, 150, 161, 119, 224, 89, 221, 37, 165, 134, 252, 213, 37,
//         150, 44, 153, 59, 188, 35, 232, 251, 106, 5, 232, 17, 110, 39, 254, 70, 27, 250, 124, 44,
//         184, 109, 168, 69, 19, 165, 122, 114, 91, 114, 83, 16, 10, 189, 128, 253, 33, 43, 212, 183,
//         241, 164, 29, 248, 49, 41, 241, 24, 30, 169, 213, 223, 96, 237, 22, 30, 28, 84, 199, 234,
//         131, 201, 201, 249, 192, 192, 77, 227, 62, 45, 12, 12, 93, 125, 238, 122, 154, 204, 35, 9,
//         170, 231, 68, 120, 183, 29, 140, 40, 165, 151, 14, 252, 76, 87, 38, 216, 68, 14, 33, 176,
//         17,
//     ];

//     // Clear tx
//     let tx = clear_vapp_tx(
//         requester_signer, // requester
//         bidder_signer,    // bidder
//         fulfiller_signer, // fulfiller
//         settle_signer,    // settle_signer
//         executor_signer,  // executor
//         verifier_signer,  // verifier
//         request_body,
//         1,                // bid_nonce
//         U256::from(10e6), // bid_amount
//         1,                // settle_nonce
//         1,                // fulfill_nonce
//         proof,
//         1, // execute_nonce
//         ExecutionStatus::Executed,
//         Some([0; 8]), // vk_digest_array
//         None,         // pv_digest_array
//     );
//     test.state.execute::<MockVerifier>(&tx).unwrap();

//     assert_eq!(
//         test.state.accounts.get(&account_address).unwrap().get_balance(),
//         U256::from(90e6 as u64),
//     );
// }

// #[test]
// #[allow(clippy::too_many_lines)]
// fn test_complex_workflow() {
//     let mut test = setup();

//     // Counters for maintaining tx ordering.
//     let mut receipt_counter = 0;
//     let mut log_index_counter = 0;
//     let mut block_counter = 0;

//     // Additional signers for this complex workflow.
//     let user1_signer = signer("user1");
//     let user2_signer = signer("user2");
//     let user3_signer = signer("user3");
//     let prover1_signer = signer("prover1");
//     let prover2_signer = signer("prover2");
//     let delegated_prover1_signer = signer("delegated_prover1");
//     let delegated_prover2_signer = signer("delegated_prover2");

//     // Helper to create txs with proper ordering.
//     let mut next_receipt = || {
//         receipt_counter += 1;
//         receipt_counter
//     };
//     let mut next_log_index = || {
//         log_index_counter += 1;
//         log_index_counter
//     };
//     let mut next_block = || {
//         block_counter += 1;
//         block_counter
//     };

//     // === SETUP PHASE: Multiple deposits and delegated signers ===

//     let txs = vec![
//         // User1 deposits 1000 tokens.
//         VAppTransaction::Deposit(OnchainTransaction {
//             tx_hash: None,
//             block: next_block(),
//             log_index: next_log_index(),
//             onchain_tx: next_receipt(),
//             action: Deposit { account: user1_signer.address(), amount: U256::from(1000e6) },
//         }),
//         // User2 deposits 500 tokens.
//         VAppTransaction::Deposit(OnchainTransaction {
//             tx_hash: None,
//             block: next_block(),
//             log_index: next_log_index(),
//             onchain_tx: next_receipt(),
//             action: Deposit { account: user2_signer.address(), amount: U256::from(500e6) },
//         }),
//         // User3 deposits 750 tokens.
//         VAppTransaction::Deposit(OnchainTransaction {
//             tx_hash: None,
//             block: next_block(),
//             log_index: next_log_index(),
//             onchain_tx: next_receipt(),
//             action: Deposit { account: user3_signer.address(), amount: U256::from(750e6) },
//         }),
//         // User1 adds delegated signer1.
//         VAppTransaction::CreateProver(OnchainTransaction {
//             tx_hash: None,
//             block: next_block(),
//             log_index: next_log_index(),
//             onchain_tx: next_receipt(),
//             action: CreateProver {
//                 prover: prover1_signer.address(),
//                 owner: delegated_prover1_signer.address(),
//                 stakerFeeBips: U256::from(0),
//             },
//         }),
//         // User2 adds delegated signer2.
//         VAppTransaction::CreateProver(OnchainTransaction {
//             tx_hash: None,
//             block: next_block(),
//             log_index: next_log_index(),
//             onchain_tx: next_receipt(),
//             action: CreateProver {
//                 prover: prover2_signer.address(),
//                 owner: delegated_prover2_signer.address(),
//                 stakerFeeBips: U256::from(0),
//             },
//         }),
//     ];

//     // Apply setup txs.
//     let mut action_count = 0;
//     for tx in txs {
//         if let Ok(Some(_)) = test.state.execute::<MockVerifier>(&tx) {
//             action_count += 1;
//         }
//     }

//     // Verify initial state after deposits and delegations.
//     assert_eq!(
//         test.state.accounts.get(&user1_signer.address()).unwrap().get_balance(),
//         U256::from(1000e6)
//     );
//     assert_eq!(
//         test.state.accounts.get(&user2_signer.address()).unwrap().get_balance(),
//         U256::from(500e6)
//     );
//     assert_eq!(
//         test.state.accounts.get(&user3_signer.address()).unwrap().get_balance(),
//         U256::from(750e6)
//     );
//     assert_eq!(action_count, 5);

//     // === CLEAR PHASE: Multiple proof clearing operations ===

//     let proof = vec![
//         17, 182, 160, 157, 40, 242, 129, 34, 129, 204, 131, 191, 247, 169, 187, 69, 119, 90, 227,
//         82, 88, 207, 116, 44, 34, 113, 109, 48, 85, 75, 45, 95, 111, 205, 161, 129, 18, 175, 110,
//         238, 88, 46, 229, 251, 208, 212, 65, 200, 159, 144, 27, 252, 203, 116, 11, 243, 245, 60,
//         193, 115, 19, 186, 8, 52, 108, 195, 11, 30, 31, 12, 176, 52, 162, 22, 135, 115, 165, 161,
//         191, 161, 111, 60, 246, 104, 207, 32, 178, 36, 15, 23, 97, 222, 253, 16, 81, 231, 255, 67,
//         0, 59, 15, 140, 83, 36, 88, 90, 163, 253, 245, 233, 211, 239, 210, 154, 16, 4, 68, 40, 3,
//         4, 146, 9, 82, 199, 52, 237, 208, 4, 31, 61, 16, 233, 26, 211, 199, 211, 213, 71, 232, 95,
//         36, 28, 213, 124, 207, 120, 62, 150, 161, 119, 224, 89, 221, 37, 165, 134, 252, 213, 37,
//         150, 44, 153, 59, 188, 35, 232, 251, 106, 5, 232, 17, 110, 39, 254, 70, 27, 250, 124, 44,
//         184, 109, 168, 69, 19, 165, 122, 114, 91, 114, 83, 16, 10, 189, 128, 253, 33, 43, 212, 183,
//         241, 164, 29, 248, 49, 41, 241, 24, 30, 169, 213, 223, 96, 237, 22, 30, 28, 84, 199, 234,
//         131, 201, 201, 249, 192, 192, 77, 227, 62, 45, 12, 12, 93, 125, 238, 122, 154, 204, 35, 9,
//         170, 231, 68, 120, 183, 29, 140, 40, 165, 151, 14, 252, 76, 87, 38, 216, 68, 14, 33, 176,
//         17,
//     ];

//     // Clear 1: User1 requests proof, prover1 fulfills (cost: 100 tokens)
//     let request_body1 = RequestProofRequestBody {
//         nonce: 1,
//         vk_hash: hex::decode("005b97bb81b9ed64f9321049013a56d9633c115b076ae4144f2622d0da13d683")
//             .unwrap(),
//         version: "sp1-v3.0.0".to_string(),
//         mode: spn_network_types::ProofMode::Groth16 as i32,
//         strategy: FulfillmentStrategy::Auction.into(),
//         stdin_uri: "s3://spn-artifacts-production3/stdins/artifact_01jqcgtjr7es883amkx30sqkg9"
//             .to_string(),
//         deadline: 1000,
//         cycle_limit: 1000,
//         gas_limit: 10000,
//         min_auction_period: 0,
//         whitelist: vec![],
//         domain: SPN_SEPOLIA_V1_DOMAIN.to_vec(),
//         auctioneer: test.auctioneer.address().to_vec(),
//         executor: test.executor.address().to_vec(),
//         verifier: test.verifier.address().to_vec(),
//         public_values_hash: None,
//         base_fee: "0".to_string(),
//         max_price_per_pgu: "1000000000000000000".to_string(),
//     };

//     let clear_tx1 = clear_vapp_tx(
//         &user1_signer,             // requester
//         &prover1_signer,           // bidder
//         &delegated_prover1_signer, // prover1 (fulfiller)
//         &test.auctioneer,          // settle_signer
//         &test.executor,            // executor
//         &test.verifier,            // verifier
//         request_body1,
//         1,                 // bid_nonce
//         U256::from(100e6), // bid amount
//         1,                 // settle_nonce
//         1,                 // fulfill_nonce
//         proof.clone(),
//         1, // execute_nonce
//         ExecutionStatus::Executed,
//         Some([0; 8]), // vk_digest_array
//         None,         // pv_digest_array
//     );

//     test.state.execute::<MockVerifier>(&clear_tx1).unwrap();

//     // Verify balances after first clear.
//     assert_eq!(
//         test.state.accounts.get(&user1_signer.address()).unwrap().get_balance(),
//         U256::from(900e6)
//     );
//     assert_eq!(
//         test.state.accounts.get(&delegated_prover1_signer.address()).unwrap().get_balance(),
//         U256::from(100000000)
//     );
// }