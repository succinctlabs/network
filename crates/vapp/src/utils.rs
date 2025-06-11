//! Utilities.
//!
//! This module contains the utilities for the vApp.

use alloy_primitives::Address;

use crate::errors::{VAppError, VAppPanic};

/// Converts a 32-byte array to a 8-word array in big-endian order.
pub fn bytes_to_words_be(bytes: &[u8; 32]) -> Result<[u32; 8], VAppError> {
    let mut words = [0u32; 8];
    for i in 0..8 {
        let chunk: [u8; 4] =
            bytes[i * 4..(i + 1) * 4].try_into().map_err(|_| VAppPanic::FailedToParseBytes)?;
        words[i] = u32::from_be_bytes(chunk);
    }
    Ok(words)
}

/// Converts a byte array to an address.
pub fn address(bytes: &[u8]) -> Result<Address, VAppError> {
    Address::try_from(bytes).map_err(|_| VAppPanic::AddressDeserializationFailed.into())
}

/// Test utilities for creating and verifying signatures.
#[cfg(test)]
#[allow(clippy::missing_panics_doc)]
pub mod tests {
    /// Signing utilities for creating and verifying signatures.
    ///
    /// This module provides helper functions for creating signers, signing protobuf messages,
    /// and building `VApp` events for testing and network operations.
    #[cfg(any(test, feature = "network"))]
    pub mod signers {
        use alloy::signers::{local::PrivateKeySigner, SignerSync};
        use alloy_primitives::{keccak256, Signature, U256};
        use prost::Message;
        use spn_network_types::{
            BidRequest, BidRequestBody, ExecuteProofRequest, ExecuteProofRequestBody,
            ExecutionStatus, FulfillProofRequest, FulfillProofRequestBody, HashableWithSender,
            MessageFormat, RequestProofRequest, RequestProofRequestBody, SetDelegationRequest,
            SetDelegationRequestBody, SettleRequest, SettleRequestBody,
        };
        use spn_utils::SPN_SEPOLIA_V1_DOMAIN;

        use crate::transactions::{ClearTransaction, DelegateTransaction, VAppTransaction};
        use alloy_primitives::Address;

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
        pub fn proto_sign<T: Message>(
            signer: &PrivateKeySigner,
            message: &T,
        ) -> Signature {
            let mut buf = Vec::new();
            message.encode(&mut buf).unwrap();
            signer.sign_message_sync(&buf).unwrap()
        }

        /// Builds a complete [`VAppEvent::Clear`] for testing.
        ///
        /// This function creates a full clear event with all required signatures and data,
        /// including request, bid, fulfill, and execute components.
        #[allow(clippy::too_many_arguments)]
        pub fn clear_vapp_event(
            requester: &PrivateKeySigner,
            prover: &PrivateKeySigner,
            delegated_prover: &PrivateKeySigner,
            settle_signer: &PrivateKeySigner,
            executor: &PrivateKeySigner,
            verifier: &PrivateKeySigner,
            request: RequestProofRequestBody,
            bid_nonce: u64,
            bid_amount: U256,
            settle_nonce: u64,
            fulfill_nonce: u64,
            proof: Vec<u8>,
            execute_nonce: u64,
            execution_status: ExecutionStatus,
            _vk_digest_array: Option<[u32; 8]>,
            pv_digest_array: Option<[u8; 32]>,
        ) -> VAppTransaction {
            // Generate request ID and signature.
            let request_id = request.hash_with_signer(requester.address().as_ref()).unwrap();
            let request_signature = proto_sign(requester, &request);

            // Create and sign bid.
            let bid = BidRequestBody {
                nonce: bid_nonce,
                request_id: request_id.to_vec(),
                amount: bid_amount.to_string(),
                domain: SPN_SEPOLIA_V1_DOMAIN.to_vec(),
                prover: prover.address().to_vec(),
            };
            let bid_signature = proto_sign(delegated_prover, &bid);

            // Create and sign settle.
            let settle = SettleRequestBody {
                nonce: settle_nonce,
                request_id: request_id.to_vec(),
                winner: prover.address().to_vec(),
                domain: SPN_SEPOLIA_V1_DOMAIN.to_vec(),
            };
            let settle_signature = proto_sign(settle_signer, &settle);

            // Create and sign fulfill.
            let fulfill = FulfillProofRequestBody {
                nonce: fulfill_nonce,
                request_id: request_id.to_vec(),
                proof,
                reserved_metadata: None,
                domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
            };
            let fulfill_signature = proto_sign(delegated_prover, &fulfill);

            // Create and sign execute.
            let execute = ExecuteProofRequestBody {
                nonce: execute_nonce,
                request_id: request_id.to_vec(),
                execution_status: execution_status.into(),
                public_values_hash: Some(
                    pv_digest_array.map(|arr| arr.to_vec()).unwrap_or(vec![0; 32]),
                ),
                cycles: None,
                pgus: Some(1),
                domain: spn_utils::SPN_SEPOLIA_V1_DOMAIN.to_vec(),
            };
            let execute_signature = proto_sign(executor, &execute);

            // Sign the request ID with the verifier's private key.
            let fulfill_id = fulfill.hash_with_signer(delegated_prover.address().as_ref()).unwrap();
            let verifier_signature = verifier.sign_message_sync(&fulfill_id).unwrap();

            VAppTransaction::Clear(ClearTransaction {
                request: RequestProofRequest {
                    format: MessageFormat::Binary.into(),
                    body: Some(request),
                    signature: request_signature.as_bytes().to_vec(),
                },
                bid: BidRequest {
                    format: MessageFormat::Binary.into(),
                    body: Some(bid),
                    signature: bid_signature.as_bytes().to_vec(),
                },
                settle: SettleRequest {
                    format: MessageFormat::Binary.into(),
                    body: Some(settle),
                    signature: settle_signature.as_bytes().to_vec(),
                },
                fulfill: FulfillProofRequest {
                    format: MessageFormat::Binary.into(),
                    body: Some(fulfill),
                    signature: fulfill_signature.as_bytes().to_vec(),
                },
                execute: ExecuteProofRequest {
                    format: MessageFormat::Binary.into(),
                    body: Some(execute),
                    signature: execute_signature.as_bytes().to_vec(),
                },
                verify: verifier_signature.as_bytes().to_vec(),
                vk: None,
            })
        }

        /// Builds a complete [`VAppEvent::Delegate`] for testing.
        ///
        /// This function creates a delegation event with proper signature verification,
        /// simulating the process where a prover owner delegates authority to another account.
        pub fn delegate_vapp_event(
            prover_owner: &PrivateKeySigner,
            prover_address: Address,
            delegate_address: Address,
            nonce: u64,
        ) -> VAppTransaction {
            // Create the delegation request body.
            let body = SetDelegationRequestBody {
                nonce,
                delegate: delegate_address.to_vec(),
                domain: SPN_SEPOLIA_V1_DOMAIN.to_vec(),
                prover: prover_address.to_vec(),
            };

            // Sign the delegation request with the prover owner's key.
            let signature = proto_sign(prover_owner, &body);

            VAppTransaction::Delegate(DelegateTransaction {
                delegation: SetDelegationRequest {
                    format: MessageFormat::Binary.into(),
                    body: Some(body),
                    signature: signature.as_bytes().to_vec(),
                },
            })
        }
    }

    /// Test utilities for setting up test environments.
    ///
    /// This module provides common test setup functions and utilities for creating
    /// test states, domains, and signers.
    #[cfg(any(test, feature = "network"))]
    pub mod test_utils {
        use std::time::{SystemTime, UNIX_EPOCH};

        use alloy::signers::local::PrivateKeySigner;
        use alloy_primitives::Address;
        use spn_utils::SPN_SEPOLIA_V1_DOMAIN;

        use crate::{merkle::MerkleStorage, sol::Account, state::VAppState, storage::RequestId};

        use super::signers::signer;

        /// Test environment containing state, domain, and signers.
        pub struct TestEnvironment {
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
            pub prover: PrivateKeySigner,
            /// The signers for the test environment.
            pub signers: Vec<PrivateKeySigner>,
        }

        /// Gets the current timestamp as seconds since Unix epoch.
        #[must_use]
        pub fn timestamp() -> i64 {
            SystemTime::now().duration_since(UNIX_EPOCH).expect("time went backwards").as_secs()
                as i64
        }

        /// Sets up a test environment with initialized state and signers.
        ///
        /// Creates a new state with a local domain and 10 test signers.
        #[must_use]
        pub fn setup() -> TestEnvironment {
            let domain = *SPN_SEPOLIA_V1_DOMAIN;
            let treasury = signer("treasury");
            let auctioneer = signer("auctioneer");
            let executor = signer("executor");
            let verifier = signer("verifier");
            let state = VAppState::new(
                domain,
                treasury.address(),
                auctioneer.address(),
                executor.address(),
                verifier.address(),
            );
            TestEnvironment {
                state,
                auctioneer,
                executor,
                verifier,
                requester: signer("requester"),
                prover: signer("prover"),
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
    }
}
