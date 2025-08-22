mod common;

use alloy_primitives::U256;
use spn_network_types::{MessageFormat, TransactionVariant, TransferRequest, TransferRequestBody};
use spn_vapp_core::{
    errors::VAppPanic,
    transactions::{TransferTransaction, VAppTransaction},
    verifier::MockVerifier,
};

use crate::common::*;

// Helper to create PROVE amounts
fn prove(amount: u64) -> U256 {
    U256::from(amount) * U256::from(10).pow(U256::from(18))
}

#[test]
fn test_transfer_basic() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let amount = prove(2); // 2 PROVE
    let fee = prove(1); // 1 PROVE

    // Set up initial balance for sender.
    let initial_balance = prove(10); // 10 PROVE
    let deposit_tx = deposit_tx(from_signer.address(), initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&mut test, from_signer.address(), initial_balance);

    // Execute transfer.
    let transfer_tx = transfer_tx(&from_signer, to_address, amount, 1, auctioneer, fee);
    let result = test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify transfer does not return a receipt.
    assert!(result.is_none());

    // Verify balances were updated correctly.
    // Sender should have: initial - amount - fee = 10 - 2 - 1 = 7 PROVE
    assert_account_balance(&mut test, from_signer.address(), prove(7));
    // Recipient should have: amount = 2 PROVE
    assert_account_balance(&mut test, to_address, amount);
    // Auctioneer should have: fee = 1 PROVE
    assert_account_balance(&mut test, auctioneer, fee);

    // Verify state counters (only tx_id increments for off-chain transactions).
    assert_state_counters(&test, 3, 2, 0, 1);
}

#[test]
fn test_transfer_self_transfer() {
    let mut test = setup();
    let signer = test.signers[0].clone();
    let auctioneer = test.auctioneer.address();
    let amount = prove(2); // 2 PROVE
    let fee = prove(1); // 1 PROVE

    // Set up initial balance.
    let initial_balance = prove(10); // 10 PROVE
    let deposit_tx = deposit_tx(signer.address(), initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute self-transfer.
    let transfer_tx = transfer_tx(&signer, signer.address(), amount, 1, auctioneer, fee);
    let result = test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify transfer succeeds.
    assert!(result.is_none());
    // Self-transfer: sender gets amount but pays fee, so balance = 10 - 1 = 9 PROVE
    assert_account_balance(&mut test, signer.address(), prove(9));
    // Auctioneer gets the fee
    assert_account_balance(&mut test, auctioneer, fee);
}

#[test]
fn test_transfer_multiple_transfers() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to1 = test.signers[1].address();
    let to2 = test.signers[2].address();
    let to3 = test.signers[3].address();
    let auctioneer = test.auctioneer.address();
    let fee = prove(1); // 1 PROVE

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), prove(20), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute first transfer.
    let transfer1 = transfer_tx(&from_signer, to1, prove(3), 1, auctioneer, fee);
    test.state.execute::<MockVerifier>(&transfer1).unwrap();
    // Balance: 20 - 3 - 1 = 16 PROVE
    assert_account_balance(&mut test, from_signer.address(), prove(16));
    assert_account_balance(&mut test, to1, prove(3));

    // Execute second transfer.
    let transfer2 = transfer_tx(&from_signer, to2, prove(5), 2, auctioneer, fee);
    test.state.execute::<MockVerifier>(&transfer2).unwrap();
    // Balance: 16 - 5 - 1 = 10 PROVE
    assert_account_balance(&mut test, from_signer.address(), prove(10));
    assert_account_balance(&mut test, to2, prove(5));

    // Execute third transfer.
    let transfer3 = transfer_tx(&from_signer, to3, prove(2), 3, auctioneer, fee);
    test.state.execute::<MockVerifier>(&transfer3).unwrap();
    // Balance: 10 - 2 - 1 = 7 PROVE
    assert_account_balance(&mut test, from_signer.address(), prove(7));
    assert_account_balance(&mut test, to3, prove(2));

    // Verify auctioneer collected 3 fees
    assert_account_balance(&mut test, auctioneer, prove(3));

    // Verify state progression.
    assert_state_counters(&test, 5, 2, 0, 1);
}

#[test]
fn test_transfer_to_new_account() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let new_account = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let amount = prove(3); // 3 PROVE
    let fee = prove(1); // 1 PROVE

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), prove(10), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Verify new account has zero balance initially.
    assert_account_balance(&mut test, new_account, U256::ZERO);

    // Execute transfer to new account.
    let transfer_tx = transfer_tx(&from_signer, new_account, amount, 1, auctioneer, fee);
    test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify new account was created with correct balance.
    // Sender: 10 - 3 - 1 = 6 PROVE
    assert_account_balance(&mut test, from_signer.address(), prove(6));
    assert_account_balance(&mut test, new_account, amount);
    assert_account_balance(&mut test, auctioneer, fee);
}

#[test]
fn test_transfer_exact_balance() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let fee = prove(1); // 1 PROVE
    let transfer_amount = prove(5); // 5 PROVE
    let initial_balance = transfer_amount + fee; // Exactly enough for transfer + fee = 6 PROVE

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute transfer with exact balance.
    let transfer_tx = transfer_tx(&from_signer, to_address, transfer_amount, 1, auctioneer, fee);
    test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify sender has zero balance after transfer.
    assert_account_balance(&mut test, from_signer.address(), U256::ZERO);
    assert_account_balance(&mut test, to_address, transfer_amount);
    assert_account_balance(&mut test, auctioneer, fee);
}

#[test]
fn test_transfer_zero_amount() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let fee = prove(1); // 1 PROVE

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), prove(5), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute zero amount transfer (still pays fee).
    let transfer_tx = transfer_tx(&from_signer, to_address, U256::ZERO, 1, auctioneer, fee);
    test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify sender pays fee even for zero transfer.
    assert_account_balance(&mut test, from_signer.address(), prove(4)); // 5 - 1 = 4 PROVE
    assert_account_balance(&mut test, to_address, U256::ZERO);
    assert_account_balance(&mut test, auctioneer, fee);
}

#[test]
fn test_transfer_insufficient_balance() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let fee = prove(1); // 1 PROVE

    // Set up initial balance.
    let initial_balance = prove(2); // 2 PROVE
    let deposit_tx = deposit_tx(from_signer.address(), initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to transfer amount that would be ok without fee, but fails with fee.
    let transfer_amount = prove(2); // Equal to balance, but no room for fee
    let transfer_tx = transfer_tx(&from_signer, to_address, transfer_amount, 1, auctioneer, fee);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned with total amount (transfer + fee).
    let expected_total = transfer_amount + fee; // 2 + 1 = 3 PROVE
    assert!(matches!(
        result,
        Err(VAppPanic::InsufficientBalance {
            account,
            amount,
            balance
        }) if account == from_signer.address() && amount == expected_total && balance == initial_balance
    ));

    // Verify balances remain unchanged.
    assert_account_balance(&mut test, from_signer.address(), initial_balance);
    assert_account_balance(&mut test, to_address, U256::ZERO);
    assert_account_balance(&mut test, auctioneer, U256::ZERO);
    assert_state_counters(&test, 2, 2, 0, 1);
}

#[test]
fn test_transfer_from_zero_balance_account() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let fee = prove(1); // 1 PROVE

    // Try to transfer from account with zero balance.
    let transfer_amount = prove(1); // 1 PROVE
    let transfer_tx = transfer_tx(&from_signer, to_address, transfer_amount, 1, auctioneer, fee);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned with total amount.
    let expected_total = transfer_amount + fee; // 1 + 1 = 2 PROVE
    assert!(matches!(
        result,
        Err(VAppPanic::InsufficientBalance {
            account,
            amount,
            balance
        }) if account == from_signer.address() && amount == expected_total && balance == U256::ZERO
    ));

    // Verify state remains unchanged.
    assert_state_counters(&test, 1, 1, 0, 0);
}

#[test]
fn test_transfer_from_signer_without_balance() {
    let mut test = setup();
    let from_signer_with_balance = test.signers[0].clone();
    let from_signer_without_balance = test.signers[1].clone();
    let to_address = test.signers[2].address();
    let auctioneer = test.auctioneer.address();
    let fee = U256::from(10).pow(U256::from(18)); // 1 PROVE

    // Set up initial balance for one signer.
    let deposit_tx = deposit_tx(from_signer_with_balance.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create transfer signed by signer without balance (this tests the logic properly).
    let transfer_amount = U256::from(100);
    let transfer_tx =
        transfer_tx(&from_signer_without_balance, to_address, transfer_amount, 1, auctioneer, fee);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned (signer has insufficient balance).
    let expected_total = transfer_amount + fee;
    assert!(matches!(
        result,
        Err(VAppPanic::InsufficientBalance {
            account,
            amount,
            balance
        }) if account == from_signer_without_balance.address() && amount == expected_total && balance == U256::ZERO
    ));

    // Verify balances remain unchanged.
    assert_account_balance(&mut test, from_signer_with_balance.address(), U256::from(500));
    assert_account_balance(&mut test, from_signer_without_balance.address(), U256::ZERO);
    assert_account_balance(&mut test, to_address, U256::ZERO);
    assert_account_balance(&mut test, auctioneer, U256::ZERO);
}

#[test]
fn test_transfer_domain_mismatch() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let fee = U256::from(10).pow(U256::from(18)); // 1 PROVE

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to transfer with wrong domain.
    let wrong_domain = [1u8; 32];
    let transfer_tx = transfer_tx_with_domain(
        &from_signer,
        to_address,
        U256::from(100),
        1,
        wrong_domain,
        auctioneer,
        fee,
    );
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::DomainMismatch { .. })));

    // Verify balances remain unchanged.
    assert_account_balance(&mut test, from_signer.address(), U256::from(500));
    assert_account_balance(&mut test, to_address, U256::ZERO);
    assert_account_balance(&mut test, auctioneer, U256::ZERO);
}

#[test]
fn test_transfer_missing_body() {
    let mut test = setup();

    // Try to execute transfer with missing body.
    let transfer_tx = transfer_tx_missing_body();
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::MissingProtoBody)));

    // Verify state remains unchanged.
    assert_state_counters(&test, 1, 1, 0, 0);
}

#[test]
fn test_transfer_invalid_amount_parsing() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let fee = U256::from(10).pow(U256::from(18)); // 1 PROVE

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to transfer with invalid amount string.
    let transfer_tx =
        transfer_tx_invalid_amount(&from_signer, to_address, "invalid_amount", 1, auctioneer, fee);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::InvalidTransferAmount { .. })));

    // Verify balances remain unchanged.
    assert_account_balance(&mut test, from_signer.address(), U256::from(500));
    assert_account_balance(&mut test, to_address, U256::ZERO);
    assert_account_balance(&mut test, auctioneer, U256::ZERO);
}

#[test]
fn test_transfer_invalid_to_address() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let auctioneer = test.auctioneer.address();
    let fee = U256::from(10).pow(U256::from(18)); // 1 PROVE

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create transfer with invalid to address (too short).
    let body = TransferRequestBody {
        nonce: 1,
        to: vec![0x12, 0x34], // Invalid - too short
        amount: U256::from(100).to_string(),
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::TransferVariant as i32,
        auctioneer: auctioneer.to_vec(),
        fee: fee.to_string(),
    };
    let signature = proto_sign(&from_signer, &body);

    let transfer_tx = VAppTransaction::Transfer(TransferTransaction {
        transfer: TransferRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    });

    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::AddressDeserializationFailed)));

    // Verify balance remains unchanged.
    assert_account_balance(&mut test, from_signer.address(), U256::from(500));
    assert_account_balance(&mut test, auctioneer, U256::ZERO);
}

#[test]
fn test_transfer_replay_protection() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let amount = prove(2); // 2 PROVE
    let fee = prove(1); // 1 PROVE

    // Set up initial balance for sender.
    let deposit_tx = deposit_tx(from_signer.address(), prove(10), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&mut test, from_signer.address(), prove(10));

    // Execute first transfer.
    let transfer_tx = transfer_tx(&from_signer, to_address, amount, 1, auctioneer, fee);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify first transfer succeeds.
    assert!(result.is_ok());
    // Sender: 10 - 2 - 1 = 7 PROVE
    assert_account_balance(&mut test, from_signer.address(), prove(7));
    assert_account_balance(&mut test, to_address, amount);
    assert_account_balance(&mut test, auctioneer, fee);

    // Attempt to execute the exact same transfer transaction again.
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the second execution fails with TransactionAlreadyProcessed error.
    assert!(matches!(result, Err(VAppPanic::TransactionAlreadyProcessed { .. })));

    // Verify balances remain unchanged after replay attempt.
    assert_account_balance(&mut test, from_signer.address(), prove(7));
    assert_account_balance(&mut test, to_address, amount);
    assert_account_balance(&mut test, auctioneer, fee);
    assert_state_counters(&test, 3, 2, 0, 1);
}

#[test]
fn test_transfer_invalid_fee_parsing() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to transfer with invalid fee string.
    let transfer_tx = transfer_tx_invalid_fee(
        &from_signer,
        to_address,
        U256::from(100),
        1,
        auctioneer,
        "not_a_number",
    );
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(
        matches!(result, Err(VAppPanic::InvalidU256Amount { amount }) if amount == "not_a_number")
    );

    // Verify balances remain unchanged.
    assert_account_balance(&mut test, from_signer.address(), U256::from(500));
    assert_account_balance(&mut test, to_address, U256::ZERO);
    assert_account_balance(&mut test, auctioneer, U256::ZERO);
}

#[test]
fn test_transfer_invalid_auctioneer_address() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let fee = U256::from(10).pow(U256::from(18)); // 1 PROVE

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to transfer with invalid auctioneer address (too short).
    let invalid_auctioneer = vec![0xAA, 0xBB]; // Too short
    let transfer_tx = transfer_tx_invalid_auctioneer(
        &from_signer,
        to_address,
        U256::from(100),
        1,
        invalid_auctioneer,
        fee,
    );
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::AddressDeserializationFailed)));

    // Verify balances remain unchanged.
    assert_account_balance(&mut test, from_signer.address(), U256::from(500));
    assert_account_balance(&mut test, to_address, U256::ZERO);
}

#[test]
fn test_transfer_different_fee_amounts() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), prove(20), 0, 1, 1); // 20 PROVE
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Transfer with 2 PROVE fee.
    let fee1 = prove(2); // 2 PROVE
    let transfer1 = transfer_tx(&from_signer, to_address, prove(3), 1, auctioneer, fee1);
    test.state.execute::<MockVerifier>(&transfer1).unwrap();

    // Verify balances: 20 - 3 - 2 = 15 PROVE.
    assert_account_balance(&mut test, from_signer.address(), prove(15));
    assert_account_balance(&mut test, to_address, prove(3));
    assert_account_balance(&mut test, auctioneer, fee1);

    // Transfer with 0.5 PROVE fee.
    let fee2 = U256::from(10).pow(U256::from(18)) / U256::from(2); // 0.5 PROVE
    let transfer2 = transfer_tx(&from_signer, to_address, prove(4), 2, auctioneer, fee2);
    test.state.execute::<MockVerifier>(&transfer2).unwrap();

    // Verify balances: 15 - 4 - 0.5 = 10.5 PROVE.
    let expected_balance = prove(15) - prove(4) - fee2;
    assert_account_balance(&mut test, from_signer.address(), expected_balance);
    assert_account_balance(&mut test, to_address, prove(7)); // 3 + 4 = 7 PROVE
    assert_account_balance(&mut test, auctioneer, fee1 + fee2);
}

#[test]
fn test_transfer_different_auctioneers() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer1 = test.auctioneer.address();
    let auctioneer2 = test.signers[2].address(); // Different auctioneer
    let fee = prove(1); // 1 PROVE

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), prove(15), 0, 1, 1); // 15 PROVE
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // First transfer to auctioneer1.
    let transfer1 = transfer_tx(&from_signer, to_address, prove(4), 1, auctioneer1, fee);
    test.state.execute::<MockVerifier>(&transfer1).unwrap();

    // Second transfer to auctioneer2.
    let transfer2 = transfer_tx(&from_signer, to_address, prove(3), 2, auctioneer2, fee);
    test.state.execute::<MockVerifier>(&transfer2).unwrap();

    // Verify sender balance: 15 - 4 - 1 - 3 - 1 = 6 PROVE.
    assert_account_balance(&mut test, from_signer.address(), prove(6));
    assert_account_balance(&mut test, to_address, prove(7)); // 4 + 3 = 7 PROVE

    // Verify each auctioneer received their fee.
    assert_account_balance(&mut test, auctioneer1, fee);
    assert_account_balance(&mut test, auctioneer2, fee);
}

#[test]
fn test_transfer_exact_fee_balance() {
    let mut test = setup();
    let from_signer = test.signers[0].clone();
    let to_address = test.signers[1].address();
    let auctioneer = test.auctioneer.address();
    let fee = U256::from(10).pow(U256::from(18)); // 1 PROVE

    // Set up balance exactly equal to fee (no room for transfer amount).
    let deposit_tx = deposit_tx(from_signer.address(), fee, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to transfer 0 amount (should succeed with exact fee balance).
    let transfer_tx = transfer_tx(&from_signer, to_address, U256::ZERO, 1, auctioneer, fee);
    let result = test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify transfer succeeds.
    assert!(result.is_none());
    assert_account_balance(&mut test, from_signer.address(), U256::ZERO);
    assert_account_balance(&mut test, to_address, U256::ZERO);
    assert_account_balance(&mut test, auctioneer, fee);
}
