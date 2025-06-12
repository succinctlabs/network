mod common;

use alloy_primitives::U256;
use spn_vapp_core::{
    errors::{VAppError, VAppPanic},
    verifier::MockVerifier,
};

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
    assert_account_balance(&test, account, amount);
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
    assert_account_balance(&test, account, U256::from(100));

    // Execute second deposit to same account.
    let tx2 = deposit_tx(account, U256::from(200), 0, 2, 2);
    let receipt2 = test.state.execute::<MockVerifier>(&tx2).unwrap();
    assert_deposit_receipt(&receipt2, account, U256::from(200), 2);
    assert_account_balance(&test, account, U256::from(300));

    // Execute third deposit to same account.
    let tx3 = deposit_tx(account, U256::from(50), 1, 1, 3);
    let receipt3 = test.state.execute::<MockVerifier>(&tx3).unwrap();
    assert_deposit_receipt(&receipt3, account, U256::from(50), 3);
    assert_account_balance(&test, account, U256::from(350));
}

#[test]
fn test_deposit_multiple_different_accounts() {
    let mut test = setup();
    let account1 = test.requester.address();
    let account2 = test.prover.address();
    let account3 = test.auctioneer.address();

    // Execute deposit to account1.
    let tx1 = deposit_tx(account1, U256::from(100), 0, 1, 1);
    test.state.execute::<MockVerifier>(&tx1).unwrap();
    assert_account_balance(&test, account1, U256::from(100));

    // Execute deposit to account2.
    let tx2 = deposit_tx(account2, U256::from(200), 0, 2, 2);
    test.state.execute::<MockVerifier>(&tx2).unwrap();
    assert_account_balance(&test, account2, U256::from(200));

    // Execute deposit to account3.
    let tx3 = deposit_tx(account3, U256::from(300), 1, 1, 3);
    test.state.execute::<MockVerifier>(&tx3).unwrap();
    assert_account_balance(&test, account3, U256::from(300));

    // Verify all accounts maintain correct balances.
    assert_account_balance(&test, account1, U256::from(100));
    assert_account_balance(&test, account2, U256::from(200));
    assert_account_balance(&test, account3, U256::from(300));
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
    assert_account_balance(&test, account, max_amount);
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
    assert_account_balance(&test, account, U256::ZERO);
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
    assert!(matches!(
        result,
        Err(VAppError::Panic(VAppPanic::OnchainTxOutOfOrder { expected: 2, actual: 3 }))
    ));

    // Verify state remains unchanged after error.
    assert_account_balance(&test, account, U256::from(100));
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
    assert!(matches!(
        result,
        Err(VAppError::Panic(VAppPanic::BlockNumberOutOfOrder { expected: 5, actual: 3 }))
    ));

    // Verify state remains unchanged after error.
    assert_account_balance(&test, account, U256::from(100));
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
    assert!(matches!(
        result,
        Err(VAppError::Panic(VAppPanic::LogIndexOutOfOrder { current: 5, next: 5 }))
    ));

    // Try with log_index lower than current.
    let tx3 = deposit_tx(account, U256::from(100), 0, 3, 2);
    let result = test.state.execute::<MockVerifier>(&tx3);

    // Verify the correct panic error is returned.
    assert!(matches!(
        result,
        Err(VAppError::Panic(VAppPanic::LogIndexOutOfOrder { current: 5, next: 3 }))
    ));

    // Verify state remains unchanged after error.
    assert_account_balance(&test, account, U256::from(100));
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
    assert_account_balance(&test, account, U256::from(200));
    assert_deposit_receipt(&receipt2, account, U256::from(100), 2);
    assert_eq!(test.state.onchain_log_index, 6);

    // Execute third deposit at higher block (log_index can be anything).
    let tx3 = deposit_tx(account, U256::from(100), 1, 1, 3);
    let receipt3 = test.state.execute::<MockVerifier>(&tx3).unwrap();

    // Verify final state after block progression.
    assert_account_balance(&test, account, U256::from(300));
    assert_deposit_receipt(&receipt3, account, U256::from(100), 3);
    assert_state_counters(&test, 4, 4, 1, 1);
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