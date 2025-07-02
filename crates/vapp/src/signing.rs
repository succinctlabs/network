//! Signing.
//!
//! This module contains the functions for signing and verifying messages.

use alloy_primitives::{Address, Signature};
use eyre::Result;
use prost::Message;
use serde::Serialize;
use spn_network_types::MessageFormat;

use crate::errors::VAppPanic;

/// Verifies a signature for any message and returns the recovered signer address.
///
/// This function respects the format field and serializes the message accordingly:
/// - `MessageFormat::Binary`: Uses protobuf binary encoding
/// - `MessageFormat::Json`: Uses JSON serialization
///
/// If the format is neither of those, it returns an error.
pub fn verify_signed_message<T: Message + Serialize>(
    message: &T,
    signature: &[u8],
    format: MessageFormat,
) -> Result<Address, VAppPanic> {
    let message_bytes = match format {
        MessageFormat::Binary => {
            let mut bytes = Vec::new();
            message.encode(&mut bytes).map_err(|e| VAppPanic::FailedToSerializeMessage {
                format: MessageFormat::Binary.into(),
                error: e.to_string(),
            })?;
            bytes
        }
        MessageFormat::Json => {
            serde_json::to_vec(message).map_err(|e| VAppPanic::FailedToSerializeMessage {
                format: MessageFormat::Json.into(),
                error: e.to_string(),
            })?
        }
        _ => {
            return Err(VAppPanic::InvalidMessageFormat);
        }
    };

    let recovered_signer = eth_sign_verify(&message_bytes, signature)?;
    Ok(recovered_signer)
}

/// Verifies an Ethereum signature using the `personal_sign` format.
pub fn eth_sign_verify(message: &[u8], signature: &[u8]) -> Result<Address, VAppPanic> {
    let signature = Signature::from_raw(signature)
        .map_err(|e| VAppPanic::InvalidSignature { error: e.to_string() })?;
    let address = signature
        .recover_address_from_msg(message)
        .map_err(|e| VAppPanic::InvalidSignature { error: e.to_string() })?;
    Ok(address)
}

#[cfg(test)]
mod tests {
    use super::*;
    use spn_network_types::{
        BidRequestBody, ExecuteProofRequestBody, FulfillProofRequestBody, MessageFormat,
        RequestProofRequestBody, SetDelegationRequestBody, SettleRequestBody,
    };
    use std::str::FromStr;

    #[test]
    fn test_verify_request_proof_signature() {
        // Test fixture data for request proof signature verification.
        let message_hex = "0801122000000000000000000000000000000000000000000000000000000000000000001a0a7370312d76332e302e3020022803324973333a2f2f73706e2d6172746966616374732d70726f64756374696f6e332f737464696e732f61727469666163745f30316a716367746a72376573383833616d6b78333073716b673938e80740e80748904e";
        let sender_hex = "31f8dc299e8e473f6562be20c047efbb93b8f3b3";
        let signature_hex = "0861fc247bbb6ab7aa9fd9b8e199bca8fea2e448103d8995ce2f4c3bd1bbe9035b17c7655f8d1b8e6256f12a4e9f45289d8ffc55b66d0c5982489502801cb8611c";

        // Decode the message to get the RequestProofRequestBody.
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = RequestProofRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Ensure the encoded body matches the original message.
        let mut buf = Vec::new();
        decoded_body.encode(&mut buf).unwrap();
        assert_eq!(hex::encode(buf), message_hex);

        // Verify the request proof signature.
        let signature = hex::decode(signature_hex).unwrap();
        let result = verify_signed_message(&decoded_body, &signature, MessageFormat::Binary);

        // Check that signature verification succeeded.
        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());

        // Verify that the recovered signer matches the expected address.
        let recovered_signer = result.unwrap();
        let expected_address = Address::from_str(sender_hex).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_bid_request_signature() {
        // Test fixture data for bid request signature verification.
        let message_hex = "1220a3ac34d4d49db9984ec3e96578503591eb414edcd9c4f6fb865a8f6f8d81937a";
        let sender_hex = "d7cfc5088b9ad010bffa295ff89bc472a7e8ddee";
        let signature_hex = "87c923b7a44f7768fa2ab1b8ed821be5fd2339fed6694ea788d335a4968719db3bd5334d74d15861364a947dd11642bc0550774f063fed3a59cc331ddf95531e1b";

        // Decode the message to get the BidRequestBody.
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = BidRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Verify the bid request signature.
        let signature = hex::decode(signature_hex).unwrap();
        let result = verify_signed_message(&decoded_body, &signature, MessageFormat::Binary);

        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());
        let recovered_signer = result.unwrap();
        let expected_address = Address::from_str(sender_hex).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_settle_request_signature() {
        // Test fixture data for settle request signature verification.
        let message_hex = "1220a3ac34d4d49db9984ec3e96578503591eb414edcd9c4f6fb865a8f6f8d81937a";
        let sender_hex = "190c45613465c349bae30f8eb5fb7d3ee2ad698c";
        let signature_hex = "a80cb93068cd2aaa521ac84a3b0bb1b53fa313954bee9ca8b5ad4a7fa1f940806d45c115be493e185301db1d311ef3071b57375dffb02a16bf9c37a3059541701b";

        // Decode the message to get the SettleRequestBody.
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = SettleRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Verify the settle request signature.
        let signature = hex::decode(signature_hex).unwrap();
        let result = verify_signed_message(&decoded_body, &signature, MessageFormat::Binary);

        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());
        let recovered_signer = result.unwrap();
        let expected_address = Address::from_str(sender_hex).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_execute_proof_request_signature() {
        // Test fixture data for execute proof request signature verification.
        let message_hex = "089b0212203ad3bb08bb53eaa7227e55c99311b61f570a201ff19e985512d1213db0f7d4e918022220c0a9dffe36892d12d9516056f57883abf69985dc29efda572714c61b184aca7b28c4a4fe6d30f3d9ca9f01";
        let sender_hex = "29cf94C0809Bac6DFC837B5DA92D0c7F088E7Da1";
        let signature_hex = "c8a00ba5a55e4b248f0165e4a28f4cb80366078e66a7e17417542c8edc1644155e5c0a720cf73e2ffcd559d52b2511494831101d70fdc7aeaa5a63c47daaba6a1b";

        // Decode the message to get the ExecuteProofRequestBody.
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = ExecuteProofRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Decode the signature and handle optional 0x prefix.
        let signature = hex::decode(signature_hex).unwrap();
        let signature = if let Some(stripped) = signature_hex.strip_prefix("0x") {
            hex::decode(stripped).unwrap()
        } else {
            signature
        };

        let result = verify_signed_message(&decoded_body, &signature, MessageFormat::Binary);

        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());
        let recovered_signer = result.unwrap();
        // Handle case-insensitive comparison for Ethereum addresses.
        let expected_address = Address::from_str(&sender_hex.to_lowercase()).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_fulfill_proof_request_signature() {
        // Test fixture data for fulfill proof request signature verification.
        let message_hex = "08011220a3ac34d4d49db9984ec3e96578503591eb414edcd9c4f6fb865a8f6f8d81937a1a6400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        let sender_hex = "b58e45afb431fa82de4d3f6e963bd805f96141ab";
        let signature_hex = "4df69585c0f084482af1f477289e3ae38158d42ba43886085696f2f28dbad84e34bc763d4278f006d55ecd56e750772b3e1d7b7756159c1dbbcaa760d80ce7231c";

        // Decode the message to get the FulfillProofRequestBody.
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = FulfillProofRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Verify the fulfill proof request signature.
        let signature = hex::decode(signature_hex).unwrap();
        let result = verify_signed_message(&decoded_body, &signature, MessageFormat::Binary);

        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());
        let recovered_signer = result.unwrap();
        let expected_address = Address::from_str(sender_hex).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_proto_with_json_format() {
        // Example signature for a JSON-serialized SetDelegationRequestBody.
        let signature_hex = "0d4b962e356dd54b2e2b0712ed3299fbb497ded75b7668d60c97e03cbd8a6a5b53671c66e63b7d1f7aad17080b9f1d2f0a16ff569f6a29f5f0c9daab4edb68121c";
        let expected_signer = "0x2edfdc3c360452eccba1d0b94079ec83f56c1e3c";

        // Create the SetDelegationRequestBody from the JSON data.
        let delegation_body = SetDelegationRequestBody {
            nonce: 524,
            delegate: vec![
                203, 60, 102, 176, 10, 2, 114, 121, 98, 139, 21, 162, 123, 62, 10, 137, 159, 99,
                238, 130,
            ],
            prover: vec![
                199, 244, 214, 54, 63, 3, 106, 30, 80, 153, 73, 52, 192, 192, 215, 153, 252, 101,
                110, 170,
            ],
            domain: vec![
                65, 246, 90, 2, 79, 53, 248, 227, 102, 65, 194, 159, 182, 207, 20, 26, 117, 17, 9,
                160, 44, 25, 168, 249, 81, 195, 1, 159, 160, 150, 14, 155,
            ],
            variant: 5, // DELEGATE_VARIANT
            auctioneer: hex::decode("cb3c66b00a027279628b15a27b3e0a899f63ee82").unwrap(), /* Auctioneer address */
            fee: "1000000000000000000".to_string(), // 1 PROVE default fee
        };

        // Decode the signature.
        let signature = hex::decode(signature_hex).unwrap();

        // Verify using JSON format.
        let result = verify_signed_message(&delegation_body, &signature, MessageFormat::Json);

        // Check that verification succeeded.
        assert!(result.is_ok(), "JSON signature verification failed: {:?}", result.err());

        // Verify the recovered signer matches the expected address.
        let recovered_signer = result.unwrap();
        let expected_address = Address::from_str(expected_signer).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_proto_with_unspecified_format() {
        // Test that verify_signed_message returns error with UnspecifiedMessageFormat.
        let bid_body = BidRequestBody {
            nonce: 1,
            request_id: vec![0x20; 32],
            amount: "1000".to_string(),
            domain: vec![0; 32],
            prover: vec![0; 20],
            variant: 1, // BID_VARIANT
        };

        // Create a dummy signature.
        let signature = vec![0u8; 65];

        // Verify using UnspecifiedMessageFormat - should return error.
        let result =
            verify_signed_message(&bid_body, &signature, MessageFormat::UnspecifiedMessageFormat);

        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("Invalid message format"));
    }
}
