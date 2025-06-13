mod common;

use alloy_primitives::U256;
use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};
use spn_vapp_core::{
    errors::VAppPanic,
    transactions::{TransferTransaction, VAppTransaction},
    verifier::MockVerifier,
};

use crate::common::*;

#[test]
fn test_transfer_basic() {
    let mut test = setup();
    let from_signer = &test.signers[0];
    let to_address = test.signers[1].address();
    let amount = U256::from(100);

    // Set up initial balance for sender.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&test, from_signer.address(), U256::from(500));

    // Execute transfer.
    let transfer_tx = transfer_tx(from_signer, to_address, amount, 1);
    let result = test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify transfer does not return a receipt.
    assert!(result.is_none());

    // Verify balances were updated correctly.
    assert_account_balance(&test, from_signer.address(), U256::from(400));
    assert_account_balance(&test, to_address, amount);

    // Verify state counters (only tx_id increments for off-chain transactions).
    assert_state_counters(&test, 3, 2, 0, 1);
}

#[test]
fn test_transfer_self_transfer() {
    let mut test = setup();
    let signer = &test.signers[0];
    let amount = U256::from(100);

    // Set up initial balance.
    let deposit_tx = deposit_tx(signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute self-transfer.
    let transfer_tx = transfer_tx(signer, signer.address(), amount, 1);
    let result = test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify transfer succeeds and balance remains unchanged.
    assert!(result.is_none());
    assert_account_balance(&test, signer.address(), U256::from(500));
}

#[test]
fn test_transfer_multiple_transfers() {
    let mut test = setup();
    let from_signer = &test.signers[0];
    let to1 = test.signers[1].address();
    let to2 = test.signers[2].address();
    let to3 = test.signers[3].address();

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(1000), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute first transfer.
    let transfer1 = transfer_tx(from_signer, to1, U256::from(200), 1);
    test.state.execute::<MockVerifier>(&transfer1).unwrap();
    assert_account_balance(&test, from_signer.address(), U256::from(800));
    assert_account_balance(&test, to1, U256::from(200));

    // Execute second transfer.
    let transfer2 = transfer_tx(from_signer, to2, U256::from(300), 2);
    test.state.execute::<MockVerifier>(&transfer2).unwrap();
    assert_account_balance(&test, from_signer.address(), U256::from(500));
    assert_account_balance(&test, to2, U256::from(300));

    // Execute third transfer.
    let transfer3 = transfer_tx(from_signer, to3, U256::from(150), 3);
    test.state.execute::<MockVerifier>(&transfer3).unwrap();
    assert_account_balance(&test, from_signer.address(), U256::from(350));
    assert_account_balance(&test, to3, U256::from(150));

    // Verify state progression.
    assert_state_counters(&test, 5, 2, 0, 1);
}

#[test]
fn test_transfer_to_new_account() {
    let mut test = setup();
    let from_signer = &test.signers[0];
    let new_account = test.signers[1].address();
    let amount = U256::from(250);

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Verify new account has zero balance initially.
    assert_account_balance(&test, new_account, U256::ZERO);

    // Execute transfer to new account.
    let transfer_tx = transfer_tx(from_signer, new_account, amount, 1);
    test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify new account was created with correct balance.
    assert_account_balance(&test, from_signer.address(), U256::from(250));
    assert_account_balance(&test, new_account, amount);
}

#[test]
fn test_transfer_entire_balance() {
    let mut test = setup();
    let from_signer = &test.signers[0];
    let to_address = test.signers[1].address();
    let initial_balance = U256::from(789);

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), initial_balance, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute transfer of entire balance.
    let transfer_tx = transfer_tx(from_signer, to_address, initial_balance, 1);
    test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify entire balance was transferred.
    assert_account_balance(&test, from_signer.address(), U256::ZERO);
    assert_account_balance(&test, to_address, initial_balance);
}

#[test]
fn test_transfer_zero_amount() {
    let mut test = setup();
    let from_signer = &test.signers[0];
    let to_address = test.signers[1].address();

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute zero amount transfer.
    let transfer_tx = transfer_tx(from_signer, to_address, U256::ZERO, 1);
    test.state.execute::<MockVerifier>(&transfer_tx).unwrap();

    // Verify balances remain unchanged.
    assert_account_balance(&test, from_signer.address(), U256::from(500));
    assert_account_balance(&test, to_address, U256::ZERO);
}

#[test]
fn test_transfer_insufficient_balance() {
    let mut test = setup();
    let from_signer = &test.signers[0];
    let to_address = test.signers[1].address();

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(100), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to transfer more than balance.
    let transfer_tx = transfer_tx(from_signer, to_address, U256::from(150), 1);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(
        result,
        Err(VAppPanic::InsufficientBalance {
            account,
            amount,
            balance
        }) if account == from_signer.address() && amount == U256::from(150) && balance == U256::from(100)
    ));

    // Verify balances remain unchanged.
    assert_account_balance(&test, from_signer.address(), U256::from(100));
    assert_account_balance(&test, to_address, U256::ZERO);
    assert_state_counters(&test, 2, 2, 0, 1);
}

#[test]
fn test_transfer_from_zero_balance_account() {
    let mut test = setup();
    let from_signer = &test.signers[0];
    let to_address = test.signers[1].address();

    // Try to transfer from account with zero balance.
    let transfer_tx = transfer_tx(from_signer, to_address, U256::from(1), 1);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(
        result,
        Err(VAppPanic::InsufficientBalance {
            account,
            amount,
            balance
        }) if account == from_signer.address() && amount == U256::from(1) && balance == U256::ZERO
    ));

    // Verify state remains unchanged.
    assert_state_counters(&test, 1, 1, 0, 0);
}

#[test]
fn test_transfer_from_signer_without_balance() {
    let mut test = setup();
    let from_signer_with_balance = &test.signers[0];
    let from_signer_without_balance = &test.signers[1];
    let to_address = test.signers[2].address();

    // Set up initial balance for one signer.
    let deposit_tx = deposit_tx(from_signer_with_balance.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create transfer signed by signer without balance (this tests the logic properly).
    let transfer_tx = transfer_tx(from_signer_without_balance, to_address, U256::from(100), 1);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned (signer has insufficient balance).
    assert!(matches!(
        result,
        Err(VAppPanic::InsufficientBalance {
            account,
            amount,
            balance
        }) if account == from_signer_without_balance.address() && amount == U256::from(100) && balance == U256::ZERO
    ));

    // Verify balances remain unchanged.
    assert_account_balance(&test, from_signer_with_balance.address(), U256::from(500));
    assert_account_balance(&test, from_signer_without_balance.address(), U256::ZERO);
    assert_account_balance(&test, to_address, U256::ZERO);
}

#[test]
fn test_transfer_domain_mismatch() {
    let mut test = setup();
    let from_signer = &test.signers[0];
    let to_address = test.signers[1].address();

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to transfer with wrong domain.
    let wrong_domain = [1u8; 32];
    let transfer_tx =
        transfer_tx_with_domain(from_signer, to_address, U256::from(100), 1, wrong_domain);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::DomainMismatch { .. })));

    // Verify balances remain unchanged.
    assert_account_balance(&test, from_signer.address(), U256::from(500));
    assert_account_balance(&test, to_address, U256::ZERO);
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
    let from_signer = &test.signers[0];
    let to_address = test.signers[1].address();

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to transfer with invalid amount string.
    let transfer_tx = transfer_tx_invalid_amount(from_signer, to_address, "invalid_amount", 1);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::InvalidTransferAmount { .. })));

    // Verify balances remain unchanged.
    assert_account_balance(&test, from_signer.address(), U256::from(500));
    assert_account_balance(&test, to_address, U256::ZERO);
}

#[test]
fn test_transfer_invalid_to_address() {
    let mut test = setup();
    let from_signer = &test.signers[0];

    // Set up initial balance.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create transfer with invalid to address (too short).
    let body = TransferRequestBody {
        nonce: 1,
        to: vec![0x12, 0x34], // Invalid - too short
        amount: U256::from(100).to_string(),
        domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
    };
    let signature = proto_sign(from_signer, &body);

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
    assert_account_balance(&test, from_signer.address(), U256::from(500));
}

#[test]
fn test_transfer_replay_protection() {
    let mut test = setup();
    let from_signer = &test.signers[0];
    let to_address = test.signers[1].address();
    let amount = U256::from(100);

    // Set up initial balance for sender.
    let deposit_tx = deposit_tx(from_signer.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&test, from_signer.address(), U256::from(500));

    // Execute first transfer.
    let transfer_tx = transfer_tx(from_signer, to_address, amount, 1);
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify first transfer succeeds.
    assert!(result.is_ok());
    assert_account_balance(&test, from_signer.address(), U256::from(400));
    assert_account_balance(&test, to_address, amount);

    // Attempt to execute the exact same transfer transaction again.
    let result = test.state.execute::<MockVerifier>(&transfer_tx);

    // Verify the second execution fails with TransactionAlreadyProcessed error.
    assert!(matches!(result, Err(VAppPanic::TransactionAlreadyProcessed { .. })));

    // Verify balances remain unchanged after replay attempt.
    assert_account_balance(&test, from_signer.address(), U256::from(400));
    assert_account_balance(&test, to_address, amount);
    assert_state_counters(&test, 3, 2, 0, 1);
}
