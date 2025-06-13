mod common;

use alloy_primitives::U256;
use spn_network_types::{MessageFormat, SetDelegationRequest, SetDelegationRequestBody};
use spn_vapp_core::{
    errors::VAppPanic,
    transactions::{DelegateTransaction, VAppTransaction},
    verifier::MockVerifier,
};

use crate::common::*;

#[test]
fn test_delegate_basic() {
    let mut test = setup();
    let prover_owner = &test.signers[0];
    let prover_address = test.signers[1].address();
    let delegate_address = test.signers[2].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Verify initial signer is the owner.
    assert_prover_signer(&test, prover_address, prover_owner.address());

    // Execute delegation.
    let delegate_tx = delegate_tx(prover_owner, prover_address, delegate_address, 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx).unwrap();

    // Verify delegation does not return a receipt.
    assert!(result.is_none());

    // Verify the signer was updated.
    assert_prover_signer(&test, prover_address, delegate_address);

    // Verify state counters (only tx_id increments for off-chain transactions).
    assert_state_counters(&test, 3, 2, 0, 1);
}

#[test]
fn test_delegate_self_delegation() {
    let mut test = setup();
    let prover_owner = &test.signers[0];
    let prover_address = test.signers[1].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Execute self-delegation (owner delegates to themselves).
    let delegate_tx = delegate_tx(prover_owner, prover_address, prover_owner.address(), 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx).unwrap();

    // Verify delegation succeeds and signer remains the owner.
    assert!(result.is_none());
    assert_prover_signer(&test, prover_address, prover_owner.address());
}

#[test]
fn test_delegate_multiple_delegations() {
    let mut test = setup();
    let prover_owner = &test.signers[0];
    let prover_address = test.signers[1].address();
    let delegate1 = test.signers[2].address();
    let delegate2 = test.signers[3].address();
    let delegate3 = test.signers[4].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Execute first delegation.
    let delegate_tx1 = delegate_tx(prover_owner, prover_address, delegate1, 1);
    test.state.execute::<MockVerifier>(&delegate_tx1).unwrap();
    assert_prover_signer(&test, prover_address, delegate1);

    // Execute second delegation (replaces first).
    let delegate_tx2 = delegate_tx(prover_owner, prover_address, delegate2, 2);
    test.state.execute::<MockVerifier>(&delegate_tx2).unwrap();
    assert_prover_signer(&test, prover_address, delegate2);

    // Execute third delegation (replaces second).
    let delegate_tx3 = delegate_tx(prover_owner, prover_address, delegate3, 3);
    test.state.execute::<MockVerifier>(&delegate_tx3).unwrap();
    assert_prover_signer(&test, prover_address, delegate3);

    // Verify state progression.
    assert_state_counters(&test, 5, 2, 0, 1);
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

    // Delegate for first prover.
    let delegate_tx1 = delegate_tx(owner1, prover1, delegate1, 1);
    test.state.execute::<MockVerifier>(&delegate_tx1).unwrap();

    // Delegate for second prover.
    let delegate_tx2 = delegate_tx(owner2, prover2, delegate2, 1);
    test.state.execute::<MockVerifier>(&delegate_tx2).unwrap();

    // Verify both delegations.
    assert_prover_signer(&test, prover1, delegate1);
    assert_prover_signer(&test, prover2, delegate2);
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
    let prover_owner = &test.signers[0];
    let non_owner = &test.signers[1];
    let prover_address = test.signers[2].address();
    let delegate_address = test.signers[3].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Try to delegate using non-owner signer.
    let delegate_tx = delegate_tx(non_owner, prover_address, delegate_address, 1);
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::OnlyOwnerCanDelegate)));

    // Verify signer remains unchanged.
    assert_prover_signer(&test, prover_address, prover_owner.address());
    assert_state_counters(&test, 2, 2, 0, 1);
}

#[test]
fn test_delegate_domain_mismatch() {
    let mut test = setup();
    let prover_owner = &test.signers[0];
    let prover_address = test.signers[1].address();
    let delegate_address = test.signers[2].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Try to delegate with wrong domain.
    let wrong_domain = [1u8; 32];
    let delegate_tx =
        delegate_tx_with_domain(prover_owner, prover_address, delegate_address, 1, wrong_domain);
    let result = test.state.execute::<MockVerifier>(&delegate_tx);

    // Verify the correct panic error is returned.
    assert!(matches!(result, Err(VAppPanic::DomainMismatch { .. })));

    // Verify signer remains unchanged.
    assert_prover_signer(&test, prover_address, prover_owner.address());
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
    let prover_owner = &test.signers[0];
    let delegate_address = test.signers[1].address();

    // Create delegate tx with invalid prover address (too short).
    let body = SetDelegationRequestBody {
        nonce: 1,
        delegate: delegate_address.to_vec(),
        prover: vec![0x12, 0x34], // Invalid - too short
        domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
    };
    let signature = proto_sign(prover_owner, &body);

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
    let prover_owner = &test.signers[0];
    let prover_address = test.signers[1].address();

    // Create prover first.
    let create_prover_tx =
        create_prover_tx(prover_address, prover_owner.address(), U256::from(500), 0, 1, 1);
    test.state.execute::<MockVerifier>(&create_prover_tx).unwrap();

    // Create delegate tx with invalid delegate address (too short).
    let body = SetDelegationRequestBody {
        nonce: 1,
        delegate: vec![0x56, 0x78], // Invalid - too short
        prover: prover_address.to_vec(),
        domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
    };
    let signature = proto_sign(prover_owner, &body);

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
    assert_prover_signer(&test, prover_address, prover_owner.address());
}
