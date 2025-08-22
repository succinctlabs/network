mod common;

use alloy_primitives::U256;
use spn_network_types::{
    MessageFormat, SetDelegationRequest, SetDelegationRequestBody, TransactionVariant,
};
use spn_vapp_core::{
    errors::VAppPanic,
    transactions::{DelegateTransaction, VAppTransaction},
    verifier::MockVerifier,
};

use crate::common::*;

#[test]
fn test_delegate_basic() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();
    let delegate_address = test.signers[2].address();
    let auctioneer = test.auctioneer.address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit funds for prover owner to pay delegation fee (1 PROVE).
    let owner_initial_balance = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx = deposit_tx(prover_owner.address(), owner_initial_balance, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&mut test, prover_owner.address(), owner_initial_balance);

    // Verify initial signer is the owner.
    assert_prover_signer(&mut test, prover_address, prover_owner.address());

    // Execute delegation.
    let delegate_tx = delegate_tx(&prover_owner, prover_address, delegate_address, 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx).unwrap();

    // Verify delegation does not return a receipt.
    assert!(result.is_none());

    // Verify the signer was updated.
    assert_prover_signer(&mut test, prover_address, delegate_address);

    // Verify fee was deducted from prover owner and transferred to auctioneer.
    assert_account_balance(&mut test, prover_owner.address(), U256::ZERO);
    assert_account_balance(&mut test, auctioneer, owner_initial_balance);

    // Verify state counters (only tx_id increments for off-chain transactions).
    assert_state_counters(&test, 4, 3, 0, 2);
}

#[test]
fn test_delegate_self_delegation() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit funds for prover owner to pay delegation fee (1 PROVE).
    let owner_initial_balance = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx = deposit_tx(prover_owner.address(), owner_initial_balance, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute self-delegation (owner delegates to themselves).
    let delegate_tx = delegate_tx(&prover_owner, prover_address, prover_owner.address(), 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx).unwrap();

    // Verify delegation succeeds and signer remains the owner.
    assert!(result.is_none());
    assert_prover_signer(&mut test, prover_address, prover_owner.address());
}

#[test]
fn test_delegate_multiple_delegations() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();
    let delegate1 = test.signers[2].address();
    let delegate2 = test.signers[3].address();
    let delegate3 = test.signers[4].address();
    let auctioneer = test.auctioneer.address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit funds for prover owner to pay for 3 delegations (3 PROVE).
    let owner_initial_balance = U256::from(3) * U256::from(10).pow(U256::from(18)); // 3 PROVE
    let deposit_tx = deposit_tx(prover_owner.address(), owner_initial_balance, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Execute first delegation.
    let delegate_tx1 = delegate_tx(&prover_owner, prover_address, delegate1, 1);
    test.state.execute::<MockVerifier>(&delegate_tx1).unwrap();
    assert_prover_signer(&mut test, prover_address, delegate1);
    assert_account_balance(
        &mut test,
        prover_owner.address(),
        U256::from(2) * U256::from(10).pow(U256::from(18)),
    );
    assert_account_balance(&mut test, auctioneer, U256::from(10).pow(U256::from(18)));

    // Execute second delegation (replaces first).
    let delegate_tx2 = delegate_tx(&prover_owner, prover_address, delegate2, 2);
    test.state.execute::<MockVerifier>(&delegate_tx2).unwrap();
    assert_prover_signer(&mut test, prover_address, delegate2);
    assert_account_balance(&mut test, prover_owner.address(), U256::from(10).pow(U256::from(18)));
    assert_account_balance(
        &mut test,
        auctioneer,
        U256::from(2) * U256::from(10).pow(U256::from(18)),
    );

    // Execute third delegation (replaces second).
    let delegate_tx3 = delegate_tx(&prover_owner, prover_address, delegate3, 3);
    test.state.execute::<MockVerifier>(&delegate_tx3).unwrap();
    assert_prover_signer(&mut test, prover_address, delegate3);
    assert_account_balance(&mut test, prover_owner.address(), U256::ZERO);
    assert_account_balance(
        &mut test,
        auctioneer,
        U256::from(3) * U256::from(10).pow(U256::from(18)),
    );

    // Verify state progression.
    assert_state_counters(&test, 6, 3, 0, 2);
}

#[test]
fn test_delegate_multiple_provers() {
    let mut test = setup();
    let owner1 = &test.signers[0];
    let owner2 = &test.signers[1];
    let prover1 = test.signers[2].address();
    let prover2 = test.signers[3].address();
    let delegate1 = test.signers[4].address();
    let delegate2 = test.signers[5].address();

    // Create first prover.
    let create_prover1 = create_prover_tx(prover1, owner1.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover1).unwrap();

    // Create second prover.
    let create_prover2 = create_prover_tx(prover2, owner2.address(), U256::from(750), 0, 2, 2);
    test.state.execute::<MockVerifier>(&create_prover2).unwrap();

    // Deposit funds for both owners to pay delegation fees.
    let fee_amount = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx1 = deposit_tx(owner1.address(), fee_amount, 0, 3, 3);
    test.state.execute::<MockVerifier>(&deposit_tx1).unwrap();
    let deposit_tx2 = deposit_tx(owner2.address(), fee_amount, 0, 4, 4);
    test.state.execute::<MockVerifier>(&deposit_tx2).unwrap();

    // Delegate for first prover.
    let delegate_tx1 = delegate_tx(owner1, prover1, delegate1, 1);
    test.state.execute::<MockVerifier>(&delegate_tx1).unwrap();

    // Delegate for second prover.
    let delegate_tx2 = delegate_tx(owner2, prover2, delegate2, 1);
    test.state.execute::<MockVerifier>(&delegate_tx2).unwrap();

    // Verify both delegations.
    assert_prover_signer(&mut test, prover1, delegate1);
    assert_prover_signer(&mut test, prover2, delegate2);
}

#[test]
fn test_delegate_non_existent_prover() {
    let mut test = setup();
    let prover_owner = &test.signers[0];
    let non_existent_prover = test.signers[1].address();
    let delegate_address = test.signers[2].address();

    // Try to delegate for non-existent prover.
    let delegate_tx = delegate_tx(prover_owner, non_existent_prover, delegate_address, 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(
        result,
        Err(VAppPanic::ProverDoesNotExist { prover }) if prover == non_existent_prover
    ));

    // Verify state remains unchanged.
    assert_state_counters(&test, 1, 1, 0, 0);
}

#[test]
fn test_delegate_only_owner_can_delegate() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let non_owner = &test.signers[1];
    let prover_address = test.signers[2].address();
    let delegate_address = test.signers[3].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit funds for non-owner (to ensure failure is due to ownership, not balance).
    let fee_amount = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx = deposit_tx(non_owner.address(), fee_amount, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to delegate using non-owner signer.
    let delegate_tx = delegate_tx(non_owner, prover_address, delegate_address, 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::OnlyOwnerCanDelegate)));

    // Verify signer remains unchanged.
    assert_prover_signer(&mut test, prover_address, prover_owner.address());
    assert_state_counters(&test, 3, 3, 0, 2);
}

#[test]
fn test_delegate_domain_mismatch() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();
    let delegate_address = test.signers[2].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit funds for prover owner to pay delegation fee.
    let fee_amount = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx = deposit_tx(prover_owner.address(), fee_amount, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to delegate with wrong domain.
    let wrong_domain = [1u8; 32];
    let delegate_tx =
        delegate_tx_with_domain(&prover_owner, prover_address, delegate_address, 1, wrong_domain);
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::DomainMismatch { .. })));

    // Verify signer remains unchanged.
    assert_prover_signer(&mut test, prover_address, prover_owner.address());
}

#[test]
fn test_delegate_missing_body() {
    let mut test = setup();

    // Try to execute delegation with missing body.
    let delegate_tx = delegate_tx_with_missing_body();
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::MissingProtoBody)));

    // Verify state remains unchanged.
    assert_state_counters(&test, 1, 1, 0, 0);
}

#[test]
fn test_delegate_invalid_prover_address() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let delegate_address = test.signers[1].address();

    // Deposit funds for prover owner.
    let fee_amount = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx = deposit_tx(prover_owner.address(), fee_amount, 0, 1, 1);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create delegate tx with invalid prover address (too short).
    let body = SetDelegationRequestBody {
        nonce: 1,
        delegate: delegate_address.to_vec(),
        prover: vec![0x12, 0x34], // Invalid - too short
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::DelegateVariant as i32,
        auctioneer: crate::common::signer("auctioneer").address().to_vec(),
        fee: "1000000000000000000".to_string(), // 1 PROVE default fee
    };
    let signature = proto_sign(&prover_owner, &body);

    let delegate_tx = VAppTransaction::Delegate(DelegateTransaction {
        delegation: SetDelegationRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    });

    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::AddressDeserializationFailed)));
}

#[test]
fn test_delegate_invalid_delegate_address() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit funds for prover owner.
    let fee_amount = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx = deposit_tx(prover_owner.address(), fee_amount, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create delegate tx with invalid delegate address (too short).
    let body = SetDelegationRequestBody {
        nonce: 1,
        delegate: vec![0x56, 0x78], // Invalid - too short
        prover: prover_address.to_vec(),
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::DelegateVariant as i32,
        auctioneer: crate::common::signer("auctioneer").address().to_vec(),
        fee: "1000000000000000000".to_string(), // 1 PROVE default fee
    };
    let signature = proto_sign(&prover_owner, &body);

    let delegate_tx = VAppTransaction::Delegate(DelegateTransaction {
        delegation: SetDelegationRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    });

    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::AddressDeserializationFailed)));

    // Verify signer remains unchanged.
    assert_prover_signer(&mut test, prover_address, prover_owner.address());
}

#[test]
fn test_delegate_replay_protection() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();
    let delegate_address = test.signers[2].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit funds for prover owner (enough for only one delegation).
    let fee_amount = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx1 = deposit_tx(prover_owner.address(), fee_amount, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx1).unwrap();

    // Execute first delegation.
    let delegate_tx = delegate_tx(&prover_owner, prover_address, delegate_address, 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify first delegation succeeds.
    assert!(result.is_ok());
    assert_prover_signer(&mut test, prover_address, delegate_address);

    // Deposit more funds to ensure failure is due to replay, not insufficient balance.
    let deposit_tx2 = deposit_tx(prover_owner.address(), fee_amount, 0, 3, 3);
    test.state.execute::<MockVerifier>(&deposit_tx2).unwrap();

    // Attempt to execute the exact same delegation transaction again.
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the second execution fails with TransactionAlreadyProcessed error.
    assert!(matches!(result, Err(VAppPanic::TransactionAlreadyProcessed { .. })));

    // Verify the delegation state remains unchanged after replay attempt.
    assert_prover_signer(&mut test, prover_address, delegate_address);
    assert_state_counters(&test, 5, 4, 0, 3);
}

#[test]
fn test_delegate_invalid_transaction_variant() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();
    let delegate_address = test.signers[2].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit funds for prover owner.
    let fee_amount = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx = deposit_tx(prover_owner.address(), fee_amount, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Create delegate tx with invalid variant.
    let body = SetDelegationRequestBody {
        nonce: 1,
        delegate: delegate_address.to_vec(),
        prover: prover_address.to_vec(),
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::TransferVariant as i32, // Invalid variant - should be DelegateVariant
        auctioneer: crate::common::signer("auctioneer").address().to_vec(),
        fee: "1000000000000000000".to_string(), // 1 PROVE default fee
    };
    let signature = proto_sign(&prover_owner, &body);

    let delegate_tx = VAppTransaction::Delegate(DelegateTransaction {
        delegation: SetDelegationRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    });

    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::InvalidTransactionVariant)));

    // Verify signer remains unchanged.
    assert_prover_signer(&mut test, prover_address, prover_owner.address());
}

#[test]
fn test_delegate_exact_balance() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();
    let delegate_address = test.signers[2].address();
    let auctioneer = test.auctioneer.address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit exactly 1 PROVE (exact fee amount).
    let exact_fee = U256::from(10).pow(U256::from(18)); // 1 PROVE
    let deposit_tx = deposit_tx(prover_owner.address(), exact_fee, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();
    assert_account_balance(&mut test, prover_owner.address(), exact_fee);

    // Execute delegation with exact fee amount.
    let delegate_tx = delegate_tx(&prover_owner, prover_address, delegate_address, 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx).unwrap();

    // Verify delegation succeeds.
    assert!(result.is_none());
    assert_prover_signer(&mut test, prover_address, delegate_address);

    // Verify exact fee was transferred, leaving zero balance.
    assert_account_balance(&mut test, prover_owner.address(), U256::ZERO);
    assert_account_balance(&mut test, auctioneer, exact_fee);
}

#[test]
fn test_delegate_insufficient_balance() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();
    let delegate_address = test.signers[2].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Deposit less than fee amount (0.5 PROVE).
    let insufficient_amount = U256::from(5) * U256::from(10).pow(U256::from(17)); // 0.5 PROVE
    let deposit_tx = deposit_tx(prover_owner.address(), insufficient_amount, 0, 2, 2);
    test.state.execute::<MockVerifier>(&deposit_tx).unwrap();

    // Try to delegate with insufficient balance.
    let delegate_tx = delegate_tx(&prover_owner, prover_address, delegate_address, 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::InsufficientBalance { .. })));

    // Verify signer remains unchanged.
    assert_prover_signer(&mut test, prover_address, prover_owner.address());
    assert_account_balance(&mut test, prover_owner.address(), insufficient_amount);
}

#[test]
fn test_delegate_zero_balance_owner() {
    let mut test = setup();
    let prover_owner = test.signers[0].clone();
    let prover_address = test.signers[1].address();
    let delegate_address = test.signers[2].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Try to delegate with zero balance (no prior deposit).
    let delegate_tx = delegate_tx(&prover_owner, prover_address, delegate_address, 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::InsufficientBalance { .. })));

    // Verify signer remains unchanged.
    assert_prover_signer(&mut test, prover_address, prover_owner.address());
}
