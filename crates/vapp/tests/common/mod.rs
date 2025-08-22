#![allow(dead_code)]

use std::time::{SystemTime, UNIX_EPOCH};

use alloy::signers::{local::PrivateKeySigner, SignerSync};
use alloy_primitives::{keccak256, Address, Signature, U256};
use prost::Message;
use spn_network_types::{
    BidRequest, BidRequestBody, ExecuteProofRequest, ExecuteProofRequestBody, ExecutionStatus,
    FulfillProofRequest, FulfillProofRequestBody, FulfillmentStrategy, MessageFormat, ProofMode,
    RequestProofRequest, RequestProofRequestBody, SetDelegationRequest, SetDelegationRequestBody,
    SettleRequest, SettleRequestBody, TransactionVariant, WithdrawRequest, WithdrawRequestBody,
};
use spn_utils::SPN_MAINNET_V1_DOMAIN;
use spn_vapp_core::{
    merkle::MerkleStorage,
    receipts::VAppReceipt,
    sol::{Account, CreateProver, Deposit, TransactionStatus},
    state::VAppState,
    storage::{RequestId, Storage},
    transactions::{
        ClearTransaction, DelegateTransaction, OnchainTransaction, TransferTransaction,
        VAppTransaction, WithdrawTransaction,
    },
};

/// Creates a signer from a string key.
///
/// The key is hashed using keccak256 to generate the private key.
#[must_use]
pub fn signer(key: &str) -> PrivateKeySigner {
    PrivateKeySigner::from_bytes(&keccak256(key)).unwrap()
}

/// Signs a protobuf message using a signer.
///
/// The message is encoded to bytes and then signed using the provided signer.
pub fn proto_sign<T: Message>(signer: &PrivateKeySigner, message: &T) -> Signature {
    let mut buf = Vec::new();
    message.encode(&mut buf).unwrap();
    signer.sign_message_sync(&buf).unwrap()
}

/// Test environment containing state, domain, and signers.
pub struct VAppTestContext {
    /// The state of the vApp.
    pub state: VAppState<MerkleStorage<Address, Account>, MerkleStorage<RequestId, bool>>,
    /// The auctioneer signer.
    pub auctioneer: PrivateKeySigner,
    /// The executor signer.
    pub executor: PrivateKeySigner,
    /// The verifier signer.
    pub verifier: PrivateKeySigner,
    /// The requester signer.
    pub requester: PrivateKeySigner,
    /// The prover signer.
    pub fulfiller: PrivateKeySigner,
    /// The signers for the test environment.
    pub signers: Vec<PrivateKeySigner>,
}

/// Gets the current timestamp as seconds since Unix epoch.
#[must_use]
pub fn timestamp() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).expect("time went backwards").as_secs() as i64
}

/// Sets up a test environment with initialized state and signers.
///
/// Creates a new state with a local domain and 10 test signers.
#[must_use]
pub fn setup() -> VAppTestContext {
    let domain = *SPN_MAINNET_V1_DOMAIN;
    let auctioneer = signer("auctioneer");
    let executor = signer("executor");
    let verifier = signer("verifier");
    let state = VAppState::new(domain);
    VAppTestContext {
        state,
        auctioneer,
        executor,
        verifier,
        requester: signer("requester"),
        fulfiller: signer("prover"),
        signers: vec![
            signer("1"),
            signer("2"),
            signer("3"),
            signer("4"),
            signer("5"),
            signer("6"),
            signer("7"),
            signer("8"),
            signer("9"),
            signer("10"),
        ],
    }
}

/// Creates a deposit tx with the specified parameters.
pub fn deposit_tx(
    account: Address,
    amount: U256,
    block: u64,
    log_index: u64,
    onchain_tx: u64,
) -> VAppTransaction {
    VAppTransaction::Deposit(OnchainTransaction {
        tx_hash: None,
        block,
        log_index,
        onchain_tx,
        action: Deposit { account, amount },
    })
}
/// Creates a create prover tx with the specified parameters.
pub fn create_prover_tx(
    prover: Address,
    owner: Address,
    staker_fee_bips: U256,
    block: u64,
    log_index: u64,
    onchain_tx: u64,
) -> VAppTransaction {
    VAppTransaction::CreateProver(OnchainTransaction {
        tx_hash: None,
        block,
        log_index,
        onchain_tx,
        action: CreateProver { prover, owner, stakerFeeBips: staker_fee_bips },
    })
}

/// Creates a withdraw tx with the specified parameters.
pub fn withdraw_tx(
    signer: &PrivateKeySigner,
    account: Address,
    amount: U256,
    nonce: u64,
) -> VAppTransaction {
    let body = WithdrawRequestBody {
        nonce,
        account: account.to_vec(),
        amount: amount.to_string(),
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::WithdrawVariant as i32,
        auctioneer: crate::common::signer("auctioneer").address().to_vec(),
        fee: "1000000000000000000".to_string(), // 1 PROVE default fee
    };
    let signature = proto_sign(signer, &body);
    VAppTransaction::Withdraw(WithdrawTransaction {
        withdraw: WithdrawRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    })
}

/// Creates a delegate tx with the specified parameters using the test utility.
pub fn delegate_tx(
    prover_owner: &alloy::signers::local::PrivateKeySigner,
    prover_address: Address,
    delegate_address: Address,
    nonce: u64,
) -> VAppTransaction {
    let body = SetDelegationRequestBody {
        nonce,
        delegate: delegate_address.to_vec(),
        prover: prover_address.to_vec(),
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::DelegateVariant as i32,
        auctioneer: crate::common::signer("auctioneer").address().to_vec(),
        fee: "1000000000000000000".to_string(), // 1 PROVE default fee
    };
    let signature = proto_sign(prover_owner, &body);
    VAppTransaction::Delegate(DelegateTransaction {
        delegation: SetDelegationRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    })
}

/// Creates a transfer tx with the specified parameters.
pub fn transfer_tx(
    from_signer: &alloy::signers::local::PrivateKeySigner,
    to: Address,
    amount: U256,
    nonce: u64,
    auctioneer: Address,
    fee: U256,
) -> VAppTransaction {
    use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};

    let body = TransferRequestBody {
        nonce,
        to: to.to_vec(),
        amount: amount.to_string(),
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::TransferVariant as i32,
        auctioneer: auctioneer.to_vec(),
        fee: fee.to_string(),
    };
    let signature = proto_sign(from_signer, &body);

    VAppTransaction::Transfer(TransferTransaction {
        transfer: TransferRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    })
}

/// Creates a transfer tx with custom domain for testing domain validation.
pub fn transfer_tx_with_domain(
    from_signer: &alloy::signers::local::PrivateKeySigner,
    to: Address,
    amount: U256,
    nonce: u64,
    domain: [u8; 32],
    auctioneer: Address,
    fee: U256,
) -> VAppTransaction {
    use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};

    let body = TransferRequestBody {
        nonce,
        to: to.to_vec(),
        amount: amount.to_string(),
        domain: domain.to_vec(),
        variant: TransactionVariant::TransferVariant as i32,
        auctioneer: auctioneer.to_vec(),
        fee: fee.to_string(),
    };
    let signature = proto_sign(from_signer, &body);

    VAppTransaction::Transfer(TransferTransaction {
        transfer: TransferRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    })
}

/// Creates a transfer tx with missing body for testing validation.
pub fn transfer_tx_missing_body() -> VAppTransaction {
    use spn_network_types::{MessageFormat, TransferRequest};

    VAppTransaction::Transfer(TransferTransaction {
        transfer: TransferRequest {
            format: MessageFormat::Binary.into(),
            body: None,
            signature: vec![],
        },
    })
}

/// Creates a transfer tx with invalid amount string for testing parsing.
pub fn transfer_tx_invalid_amount(
    from_signer: &alloy::signers::local::PrivateKeySigner,
    to: Address,
    invalid_amount: &str,
    nonce: u64,
    auctioneer: Address,
    fee: U256,
) -> VAppTransaction {
    use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};

    let body = TransferRequestBody {
        nonce,
        to: to.to_vec(),
        amount: invalid_amount.to_string(),
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::TransferVariant as i32,
        auctioneer: auctioneer.to_vec(),
        fee: fee.to_string(),
    };
    let signature = proto_sign(from_signer, &body);

    VAppTransaction::Transfer(TransferTransaction {
        transfer: TransferRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    })
}

/// Creates a transfer tx with invalid fee string for testing parsing.
pub fn transfer_tx_invalid_fee(
    from_signer: &alloy::signers::local::PrivateKeySigner,
    to: Address,
    amount: U256,
    nonce: u64,
    auctioneer: Address,
    invalid_fee: &str,
) -> VAppTransaction {
    use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};

    let body = TransferRequestBody {
        nonce,
        to: to.to_vec(),
        amount: amount.to_string(),
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::TransferVariant as i32,
        auctioneer: auctioneer.to_vec(),
        fee: invalid_fee.to_string(),
    };
    let signature = proto_sign(from_signer, &body);

    VAppTransaction::Transfer(TransferTransaction {
        transfer: TransferRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    })
}

/// Creates a transfer tx with invalid auctioneer address for testing parsing.
pub fn transfer_tx_invalid_auctioneer(
    from_signer: &alloy::signers::local::PrivateKeySigner,
    to: Address,
    amount: U256,
    nonce: u64,
    invalid_auctioneer: Vec<u8>,
    fee: U256,
) -> VAppTransaction {
    use spn_network_types::{MessageFormat, TransferRequest, TransferRequestBody};

    let body = TransferRequestBody {
        nonce,
        to: to.to_vec(),
        amount: amount.to_string(),
        domain: spn_utils::SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::TransferVariant as i32,
        auctioneer: invalid_auctioneer,
        fee: fee.to_string(),
    };
    let signature = proto_sign(from_signer, &body);

    VAppTransaction::Transfer(TransferTransaction {
        transfer: TransferRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    })
}

/// Creates a delegate tx with custom domain for testing domain validation.
pub fn delegate_tx_with_domain(
    prover_owner: &alloy::signers::local::PrivateKeySigner,
    prover_address: Address,
    delegate_address: Address,
    nonce: u64,
    domain: [u8; 32],
) -> VAppTransaction {
    use spn_network_types::{MessageFormat, SetDelegationRequest, SetDelegationRequestBody};

    let body = SetDelegationRequestBody {
        nonce,
        delegate: delegate_address.to_vec(),
        prover: prover_address.to_vec(),
        domain: domain.to_vec(),
        variant: TransactionVariant::DelegateVariant as i32,
        auctioneer: crate::common::signer("auctioneer").address().to_vec(),
        fee: "1000000000000000000".to_string(), // 1 PROVE default fee
    };
    let signature = proto_sign(prover_owner, &body);

    VAppTransaction::Delegate(DelegateTransaction {
        delegation: SetDelegationRequest {
            format: MessageFormat::Binary.into(),
            body: Some(body),
            signature: signature.as_bytes().to_vec(),
        },
    })
}

/// Creates a delegate tx with missing body for testing validation.
pub fn delegate_tx_with_missing_body() -> VAppTransaction {
    use spn_network_types::{MessageFormat, SetDelegationRequest};

    VAppTransaction::Delegate(DelegateTransaction {
        delegation: SetDelegationRequest {
            format: MessageFormat::Binary.into(),
            body: None,
            signature: vec![],
        },
    })
}

/// Asserts that a receipt matches the expected deposit receipt structure.
#[allow(clippy::ref_option)]
pub fn assert_deposit_receipt(
    receipt: &Option<VAppReceipt>,
    expected_account: Address,
    expected_amount: U256,
    expected_onchain_tx: u64,
) {
    match receipt.as_ref().unwrap() {
        VAppReceipt::Deposit(deposit) => {
            assert_eq!(deposit.action.account, expected_account);
            assert_eq!(deposit.action.amount, expected_amount);
            assert_eq!(deposit.onchain_tx_id, expected_onchain_tx);
            assert_eq!(deposit.status, TransactionStatus::Completed);
        }
        _ => panic!("Expected a deposit receipt"),
    }
}

/// Asserts that a receipt matches the expected withdraw receipt structure.
#[allow(clippy::ref_option)]
pub fn assert_withdraw_receipt(
    receipt: &Option<VAppReceipt>,
    expected_account: Address,
    expected_amount: U256,
) {
    match receipt.as_ref().unwrap() {
        VAppReceipt::Withdraw(withdraw) => {
            assert_eq!(withdraw.action.account, expected_account);
            assert_eq!(withdraw.action.amount, expected_amount);
            assert_eq!(withdraw.status, TransactionStatus::Completed);
        }
        _ => panic!("Expected a withdraw receipt"),
    }
}

/// Asserts that a receipt matches the expected create prover receipt structure.
#[allow(clippy::ref_option)]
pub fn assert_create_prover_receipt(
    receipt: &Option<VAppReceipt>,
    expected_prover: Address,
    expected_owner: Address,
    expected_staker_fee_bips: U256,
    expected_onchain_tx: u64,
) {
    match receipt.as_ref().unwrap() {
        VAppReceipt::CreateProver(create_prover) => {
            assert_eq!(create_prover.action.prover, expected_prover);
            assert_eq!(create_prover.action.owner, expected_owner);
            assert_eq!(create_prover.action.stakerFeeBips, expected_staker_fee_bips);
            assert_eq!(create_prover.onchain_tx_id, expected_onchain_tx);
            assert_eq!(create_prover.status, TransactionStatus::Completed);
        }
        _ => panic!("Expected a create prover receipt"),
    }
}

/// Asserts that an account has the expected balance.
#[allow(clippy::ref_option)]
pub fn assert_account_balance(
    test: &mut VAppTestContext,
    account: Address,
    expected_balance: U256,
) {
    let actual_balance =
        test.state.accounts.get(&account).unwrap().map_or(U256::ZERO, Account::get_balance);
    assert_eq!(
        actual_balance, expected_balance,
        "Account balance mismatch for {account}: expected {expected_balance}, got {actual_balance}"
    );
}

/// Asserts that a prover account has the expected configuration.
pub fn assert_prover_account(
    test: &mut VAppTestContext,
    prover: Address,
    expected_owner: Address,
    expected_signer: Address,
    expected_staker_fee_bips: U256,
) {
    let account = test.state.accounts.get(&prover).unwrap().unwrap();
    assert_eq!(account.get_owner(), expected_owner, "Prover owner mismatch");
    assert_eq!(account.get_signer(), expected_signer, "Prover signer mismatch");
    assert_eq!(account.get_staker_fee_bips(), expected_staker_fee_bips, "Staker fee bips mismatch");
}

/// Asserts that a prover has the expected signer.
pub fn assert_prover_signer(test: &mut VAppTestContext, prover: Address, expected_signer: Address) {
    let account = test.state.accounts.get(&prover).unwrap().unwrap();
    assert_eq!(account.get_signer(), expected_signer, "Prover signer mismatch");
    assert!(account.is_signer(expected_signer), "Expected address should be a valid signer");
}

/// Asserts that the state counters match the expected values.
pub fn assert_state_counters(
    test: &VAppTestContext,
    expected_tx_id: u64,
    expected_onchain_tx_id: u64,
    expected_block: u64,
    expected_log_index: u64,
) {
    assert_eq!(test.state.tx_id, expected_tx_id, "tx_id mismatch");
    assert_eq!(test.state.onchain_tx_id, expected_onchain_tx_id, "onchain_tx_id mismatch");
    assert_eq!(test.state.onchain_block, expected_block, "onchain_block mismatch");
    assert_eq!(test.state.onchain_log_index, expected_log_index, "onchain_log_index mismatch");
}

/// Creates a clear transaction with the specified parameters.
#[allow(clippy::too_many_arguments)]
pub fn create_clear_tx(
    requester_signer: &PrivateKeySigner,
    bidder_signer: &PrivateKeySigner,
    fulfiller_signer: &PrivateKeySigner,
    auctioneer_signer: &PrivateKeySigner,
    executor_signer: &PrivateKeySigner,
    verifier_signer: &PrivateKeySigner,
    request_nonce: u64,
    bid_amount: U256,
    bid_nonce: u64,
    settle_nonce: u64,
    fulfill_nonce: u64,
    execute_nonce: u64,
    proof_mode: ProofMode,
    execution_status: ExecutionStatus,
    needs_verifier_signature: bool,
) -> VAppTransaction {
    create_clear_tx_with_options(
        requester_signer,
        bidder_signer,
        fulfiller_signer,
        auctioneer_signer,
        executor_signer,
        verifier_signer,
        request_nonce,
        bid_amount,
        bid_nonce,
        settle_nonce,
        fulfill_nonce,
        execute_nonce,
        proof_mode,
        execution_status,
        needs_verifier_signature,
        None,
        None,
        None,
    )
}

/// Creates a clear transaction with optional customization parameters.
#[allow(clippy::too_many_arguments)]
pub fn create_clear_tx_with_options(
    requester_signer: &PrivateKeySigner,
    bidder_signer: &PrivateKeySigner,
    fulfiller_signer: &PrivateKeySigner,
    auctioneer_signer: &PrivateKeySigner,
    executor_signer: &PrivateKeySigner,
    verifier_signer: &PrivateKeySigner,
    request_nonce: u64,
    bid_amount: U256,
    bid_nonce: u64,
    settle_nonce: u64,
    fulfill_nonce: u64,
    execute_nonce: u64,
    proof_mode: ProofMode,
    execution_status: ExecutionStatus,
    needs_verifier_signature: bool,
    whitelist: Option<Vec<Vec<u8>>>,
    base_fee: Option<&str>,
    max_price_per_pgu: Option<&str>,
) -> VAppTransaction {
    use spn_network_types::HashableWithSender;

    // Create request body with customizable parameters.
    let request_body = RequestProofRequestBody {
        nonce: request_nonce,
        vk_hash: hex::decode("005b97bb81b9ed64f9321049013a56d9633c115b076ae4144f2622d0da13d683")
            .unwrap(),
        version: "sp1-v3.0.0".to_string(),
        mode: proof_mode as i32,
        strategy: FulfillmentStrategy::Auction as i32,
        stdin_uri: "s3://spn-artifacts-production3/stdins/artifact_01jqcgtjr7es883amkx30sqkg9"
            .to_string(),
        deadline: 1000,
        cycle_limit: 1000,
        gas_limit: 10000,
        min_auction_period: 0,
        whitelist: whitelist.unwrap_or_default(),
        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
        auctioneer: auctioneer_signer.address().to_vec(),
        executor: executor_signer.address().to_vec(),
        verifier: verifier_signer.address().to_vec(),
        public_values_hash: None,
        base_fee: base_fee.unwrap_or("0").to_string(),
        max_price_per_pgu: max_price_per_pgu.unwrap_or("100000").to_string(),
        variant: TransactionVariant::RequestVariant as i32,
        treasury: signer("treasury").address().to_vec(),
    };

    // Compute the request ID from the request body and signer.
    let request_id = request_body
        .hash_with_signer(requester_signer.address().as_slice())
        .expect("Failed to hash request body");

    // Create and sign request.
    let request = RequestProofRequest {
        format: MessageFormat::Binary as i32,
        signature: proto_sign(requester_signer, &request_body).as_bytes().to_vec(),
        body: Some(request_body),
    };

    // Create bid body with computed request ID.
    let bid_body = BidRequestBody {
        nonce: bid_nonce,
        request_id: request_id.to_vec(),
        amount: bid_amount.to_string(),
        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
        prover: bidder_signer.address().to_vec(),
        variant: TransactionVariant::BidVariant as i32,
    };

    // Create and sign bid.
    let bid = BidRequest {
        format: MessageFormat::Binary as i32,
        signature: proto_sign(bidder_signer, &bid_body).as_bytes().to_vec(),
        body: Some(bid_body),
    };

    // Create settle body with computed request ID.
    let settle_body = SettleRequestBody {
        nonce: settle_nonce,
        request_id: request_id.to_vec(),
        winner: bidder_signer.address().to_vec(),
        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::SettleVariant as i32,
    };

    // Create and sign settle.
    let settle = SettleRequest {
        format: MessageFormat::Binary as i32,
        signature: proto_sign(auctioneer_signer, &settle_body).as_bytes().to_vec(),
        body: Some(settle_body),
    };

    // Create execute body with computed request ID.
    let execute_body = ExecuteProofRequestBody {
        nonce: execute_nonce,
        request_id: request_id.to_vec(),
        execution_status: execution_status as i32,
        public_values_hash: Some([0; 32].to_vec()), // Dummy public values hash
        cycles: Some(1000),
        pgus: Some(1000),
        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
        punishment: None,
        failure_cause: None,
        variant: TransactionVariant::ExecuteVariant as i32,
    };

    // Create and sign execute.
    let execute = ExecuteProofRequest {
        format: MessageFormat::Binary as i32,
        signature: proto_sign(executor_signer, &execute_body).as_bytes().to_vec(),
        body: Some(execute_body),
    };

    // Create fulfill if needed (for executed proofs).
    let fulfill = if execution_status == ExecutionStatus::Executed {
        let fulfill_body = FulfillProofRequestBody {
            nonce: fulfill_nonce,
            request_id: request_id.to_vec(),
            proof: vec![
                17, 182, 160, 157, 40, 242, 129, 34, 129, 204, 131, 191, 247, 169, 187, 69, 119,
                90, 227, 82, 88, 207, 116, 44, 34, 113, 109, 48, 85, 75, 45, 95, 111, 205, 161,
                129, 18, 175, 110, 238, 88, 46, 229, 251, 208, 212, 65, 200, 159, 144, 27, 252,
                203, 116, 11, 243, 245, 60, 193, 115, 19, 186, 8, 52, 108, 195, 11, 30, 31, 12,
                176, 52, 162, 22, 135, 115, 165, 161, 191, 161, 111, 60, 246, 104, 207, 32, 178,
                36, 15, 23, 97, 222, 253, 16, 81, 231, 255, 67, 0, 59, 15, 140, 83, 36, 88, 90,
                163, 253, 245, 233, 211, 239, 210, 154, 16, 4, 68, 40, 3, 4, 146, 9, 82, 199, 52,
                237, 208, 4, 31, 61, 16, 233, 26, 211, 199, 211, 213, 71, 232, 95, 36, 28, 213,
                124, 207, 120, 62, 150, 161, 119, 224, 89, 221, 37, 165, 134, 252, 213, 37, 150,
                44, 153, 59, 188, 35, 232, 251, 106, 5, 232, 17, 110, 39, 254, 70, 27, 250, 124,
                44, 184, 109, 168, 69, 19, 165, 122, 114, 91, 114, 83, 16, 10, 189, 128, 253, 33,
                43, 212, 183, 241, 164, 29, 248, 49, 41, 241, 24, 30, 169, 213, 223, 96, 237, 22,
                30, 28, 84, 199, 234, 131, 201, 201, 249, 192, 192, 77, 227, 62, 45, 12, 12, 93,
                125, 238, 122, 154, 204, 35, 9, 170, 231, 68, 120, 183, 29, 140, 40, 165, 151, 14,
                252, 76, 87, 38, 216, 68, 14, 33, 176, 17,
            ],
            reserved_metadata: None,
            domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
            variant: TransactionVariant::FulfillVariant as i32,
        };

        Some(FulfillProofRequest {
            format: MessageFormat::Binary as i32,
            signature: proto_sign(fulfiller_signer, &fulfill_body).as_bytes().to_vec(),
            body: Some(fulfill_body),
        })
    } else {
        None
    };

    // Create verifier signature if needed.
    let verify = if needs_verifier_signature {
        // For Groth16/Plonk modes, we need a verifier signature on the fulfillment hash.
        if let Some(ref fulfill_req) = fulfill {
            if let Some(ref fulfill_body) = fulfill_req.body {
                // Hash the fulfill body with the fulfiller signer to get the fulfillment ID.
                let fulfillment_id = fulfill_body
                    .hash_with_signer(fulfiller_signer.address().as_slice())
                    .expect("Failed to hash fulfill body");

                // Create ETH signature of the fulfillment ID.
                use alloy::signers::SignerSync;
                Some(
                    verifier_signer.sign_message_sync(&fulfillment_id).unwrap().as_bytes().to_vec(),
                )
            } else {
                None
            }
        } else {
            None
        }
    } else {
        None
    };

    VAppTransaction::Clear(ClearTransaction {
        request,
        bid,
        settle,
        execute,
        fulfill,
        verify,
        vk: None,
    })
}

/// Creates a clear transaction with custom whitelist.
#[allow(clippy::too_many_arguments)]
pub fn create_clear_tx_with_whitelist(
    requester_signer: &PrivateKeySigner,
    bidder_signer: &PrivateKeySigner,
    fulfiller_signer: &PrivateKeySigner,
    settle_signer: &PrivateKeySigner,
    executor_signer: &PrivateKeySigner,
    verifier_signer: &PrivateKeySigner,
    request_nonce: u64,
    bid_amount: U256,
    bid_nonce: u64,
    settle_nonce: u64,
    fulfill_nonce: u64,
    execute_nonce: u64,
    proof_mode: ProofMode,
    execution_status: ExecutionStatus,
    needs_verifier_signature: bool,
    whitelist: Vec<Vec<u8>>,
) -> VAppTransaction {
    create_clear_tx_with_options(
        requester_signer,
        bidder_signer,
        fulfiller_signer,
        settle_signer,
        executor_signer,
        verifier_signer,
        request_nonce,
        bid_amount,
        bid_nonce,
        settle_nonce,
        fulfill_nonce,
        execute_nonce,
        proof_mode,
        execution_status,
        needs_verifier_signature,
        Some(whitelist),
        None,
        None,
    )
}
/// Creates a clear transaction with custom base fee string for testing parsing.
#[allow(clippy::too_many_arguments)]
pub fn create_clear_tx_with_base_fee(
    requester_signer: &PrivateKeySigner,
    bidder_signer: &PrivateKeySigner,
    fulfiller_signer: &PrivateKeySigner,
    settle_signer: &PrivateKeySigner,
    executor_signer: &PrivateKeySigner,
    verifier_signer: &PrivateKeySigner,
    request_nonce: u64,
    bid_amount: U256,
    bid_nonce: u64,
    settle_nonce: u64,
    fulfill_nonce: u64,
    execute_nonce: u64,
    proof_mode: ProofMode,
    execution_status: ExecutionStatus,
    needs_verifier_signature: bool,
    base_fee: &str,
) -> VAppTransaction {
    create_clear_tx_with_options(
        requester_signer,
        bidder_signer,
        fulfiller_signer,
        settle_signer,
        executor_signer,
        verifier_signer,
        request_nonce,
        bid_amount,
        bid_nonce,
        settle_nonce,
        fulfill_nonce,
        execute_nonce,
        proof_mode,
        execution_status,
        needs_verifier_signature,
        None,
        Some(base_fee),
        None,
    )
}

/// Creates a clear transaction with custom max price string for testing parsing.
#[allow(clippy::too_many_arguments)]
pub fn create_clear_tx_with_max_price(
    requester_signer: &PrivateKeySigner,
    bidder_signer: &PrivateKeySigner,
    fulfiller_signer: &PrivateKeySigner,
    settle_signer: &PrivateKeySigner,
    executor_signer: &PrivateKeySigner,
    verifier_signer: &PrivateKeySigner,
    request_nonce: u64,
    bid_amount: U256,
    bid_nonce: u64,
    settle_nonce: u64,
    fulfill_nonce: u64,
    execute_nonce: u64,
    proof_mode: ProofMode,
    execution_status: ExecutionStatus,
    needs_verifier_signature: bool,
    max_price_per_pgu: &str,
) -> VAppTransaction {
    create_clear_tx_with_options(
        requester_signer,
        bidder_signer,
        fulfiller_signer,
        settle_signer,
        executor_signer,
        verifier_signer,
        request_nonce,
        bid_amount,
        bid_nonce,
        settle_nonce,
        fulfill_nonce,
        execute_nonce,
        proof_mode,
        execution_status,
        needs_verifier_signature,
        None,
        None,
        Some(max_price_per_pgu),
    )
}

/// Creates a clear transaction with public values hash set.
#[allow(clippy::too_many_arguments)]
pub fn create_clear_tx_with_public_values_hash(
    requester_signer: &PrivateKeySigner,
    bidder_signer: &PrivateKeySigner,
    fulfiller_signer: &PrivateKeySigner,
    settle_signer: &PrivateKeySigner,
    executor_signer: &PrivateKeySigner,
    verifier_signer: &PrivateKeySigner,
    request_nonce: u64,
    bid_amount: U256,
    bid_nonce: u64,
    settle_nonce: u64,
    fulfill_nonce: u64,
    execute_nonce: u64,
    proof_mode: ProofMode,
    execution_status: ExecutionStatus,
    needs_verifier_signature: bool,
    public_values_hash: Vec<u8>,
) -> VAppTransaction {
    use spn_network_types::HashableWithSender;

    // Create request body with customizable parameters.
    let request_body = RequestProofRequestBody {
        nonce: request_nonce,
        vk_hash: hex::decode("005b97bb81b9ed64f9321049013a56d9633c115b076ae4144f2622d0da13d683")
            .unwrap(),
        version: "sp1-v3.0.0".to_string(),
        mode: proof_mode as i32,
        strategy: FulfillmentStrategy::Auction as i32,
        stdin_uri: "s3://spn-artifacts-production3/stdins/artifact_01jqcgtjr7es883amkx30sqkg9"
            .to_string(),
        deadline: 1000,
        cycle_limit: 1000,
        gas_limit: 10000,
        min_auction_period: 0,
        whitelist: vec![],
        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
        auctioneer: settle_signer.address().to_vec(),
        executor: executor_signer.address().to_vec(),
        verifier: verifier_signer.address().to_vec(),
        public_values_hash: Some(public_values_hash.clone()),
        base_fee: "0".to_string(),
        max_price_per_pgu: "100000".to_string(),
        variant: TransactionVariant::RequestVariant as i32,
        treasury: signer("treasury").address().to_vec(),
    };

    // Compute the request ID from the request body and signer.
    let request_id = request_body
        .hash_with_signer(requester_signer.address().as_slice())
        .expect("Failed to hash request body");

    // Create and sign request.
    let request = RequestProofRequest {
        format: MessageFormat::Binary as i32,
        signature: proto_sign(requester_signer, &request_body).as_bytes().to_vec(),
        body: Some(request_body),
    };

    // Create bid body with computed request ID.
    let bid_body = BidRequestBody {
        nonce: bid_nonce,
        request_id: request_id.to_vec(),
        amount: bid_amount.to_string(),
        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
        prover: bidder_signer.address().to_vec(),
        variant: TransactionVariant::BidVariant as i32,
    };

    // Create and sign bid.
    let bid = BidRequest {
        format: MessageFormat::Binary as i32,
        signature: proto_sign(bidder_signer, &bid_body).as_bytes().to_vec(),
        body: Some(bid_body),
    };

    // Create settle body with computed request ID.
    let settle_body = SettleRequestBody {
        nonce: settle_nonce,
        request_id: request_id.to_vec(),
        winner: bidder_signer.address().to_vec(),
        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
        variant: TransactionVariant::SettleVariant as i32,
    };

    // Create and sign settle.
    let settle = SettleRequest {
        format: MessageFormat::Binary as i32,
        signature: proto_sign(settle_signer, &settle_body).as_bytes().to_vec(),
        body: Some(settle_body),
    };

    // Create execute body with computed request ID and custom public values hash.
    let execute_body = ExecuteProofRequestBody {
        nonce: execute_nonce,
        request_id: request_id.to_vec(),
        execution_status: execution_status as i32,
        public_values_hash: Some(public_values_hash),
        cycles: Some(1000),
        pgus: Some(1000),
        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
        punishment: None,
        failure_cause: None,
        variant: TransactionVariant::ExecuteVariant as i32,
    };

    // Create and sign execute.
    let execute = ExecuteProofRequest {
        format: MessageFormat::Binary as i32,
        signature: proto_sign(executor_signer, &execute_body).as_bytes().to_vec(),
        body: Some(execute_body),
    };

    // Create fulfill body.
    let fulfill_body = FulfillProofRequestBody {
        nonce: fulfill_nonce,
        request_id: request_id.to_vec(),
        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
        proof: vec![0u8; 100],
        reserved_metadata: None,
        variant: TransactionVariant::FulfillVariant as i32,
    };

    // Create and sign fulfill.
    let fulfill = FulfillProofRequest {
        format: MessageFormat::Binary as i32,
        signature: proto_sign(fulfiller_signer, &fulfill_body).as_bytes().to_vec(),
        body: Some(fulfill_body.clone()),
    };

    // Create optional verifier signature.
    let verify = if needs_verifier_signature {
        let fulfillment_id = fulfill_body
            .hash_with_signer(fulfiller_signer.address().as_slice())
            .expect("Failed to hash fulfill body");
        Some(verifier_signer.sign_message_sync(&fulfillment_id).unwrap().as_bytes().to_vec())
    } else {
        None
    };

    // Return the clear transaction.
    VAppTransaction::Clear(ClearTransaction {
        request,
        bid,
        settle,
        execute,
        fulfill: Some(fulfill),
        verify,
        vk: None,
    })
}

/// Creates a clear transaction with a mismatched auctioneer (for testing auctioneer mismatch).
#[allow(clippy::too_many_arguments)]
pub fn create_clear_tx_with_mismatched_auctioneer(
    requester_signer: &PrivateKeySigner,
    bidder_signer: &PrivateKeySigner,
    fulfiller_signer: &PrivateKeySigner,
    expected_auctioneer: &PrivateKeySigner,
    wrong_settle_signer: &PrivateKeySigner,
    executor_signer: &PrivateKeySigner,
    verifier_signer: &PrivateKeySigner,
    request_nonce: u64,
    bid_amount: U256,
    bid_nonce: u64,
    settle_nonce: u64,
    fulfill_nonce: u64,
    execute_nonce: u64,
    proof_mode: ProofMode,
    execution_status: ExecutionStatus,
    needs_verifier_signature: bool,
) -> VAppTransaction {
    // Create request with expected auctioneer but settle with wrong signer.
    let mut tx = create_clear_tx_with_options(
        requester_signer,
        bidder_signer,
        fulfiller_signer,
        expected_auctioneer, // Request auctioneer
        executor_signer,
        verifier_signer,
        request_nonce,
        bid_amount,
        bid_nonce,
        settle_nonce,
        fulfill_nonce,
        execute_nonce,
        proof_mode,
        execution_status,
        needs_verifier_signature,
        None,
        None,
        None,
    );

    // Replace the settle with wrong signer.
    if let VAppTransaction::Clear(ref mut clear) = tx {
        if let Some(ref settle_body) = clear.settle.body {
            clear.settle.signature =
                proto_sign(wrong_settle_signer, settle_body).as_bytes().to_vec();
        }
    }

    tx
}
