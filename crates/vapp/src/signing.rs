use alloy_primitives::{Address, PrimitiveSignature};
use alloy_sol_types::{eip712_domain, Eip712Domain};
use eyre::Result;
use prost::Message;
use sha2::{Digest, Sha256};

/// Build a domain for a given chain and contract address
pub fn eip_712_domain(chain_id: u64, contract: Address) -> Eip712Domain {
    let domain = eip712_domain! {
        name: "vApp",
        version: "1",
        chain_id: chain_id,
        verifying_contract: contract,
    };
    domain
}

/// Verifies a signature for any protobuf message and returns the recovered signer address
pub fn proto_verify<T: Message>(message: &T, signature: &[u8]) -> Result<Address> {
    // Encode the message to bytes
    println!("cycle-tracker-report-start: proto encode");
    let mut message_bytes = Vec::new();
    message.encode(&mut message_bytes)?;
    println!("cycle-tracker-report-end: proto encode");

    // Verify the signature against the encoded message
    println!("cycle-tracker-report-start: proto verify");
    let recovered_signer = verify_ethereum_personal_sign(&message_bytes, signature)?;
    println!("cycle-tracker-report-end: proto verify");

    Ok(recovered_signer)
}

/// Calculate the hash of a protobuf message and sender address
pub fn proto_hash<T: Message>(message: &T, sender: &Address) -> Vec<u8> {
    let tx_bytes = message.encode_to_vec();
    let mut hasher = Sha256::new();
    hasher.update(&tx_bytes);
    hasher.update(<Address as AsRef<[u8]>>::as_ref(sender));
    hasher.finalize().to_vec()
}

/// Verifies an Ethereum signature using the personal_sign format
pub fn verify_ethereum_personal_sign(message: &[u8], signature: &[u8]) -> Result<Address> {
    let signature = PrimitiveSignature::from_raw(signature)?;
    let address = signature.recover_address_from_msg(message)?;
    Ok(address)
}

#[cfg(test)]
mod tests {
    use super::*;
    use spn_network_types::{
        BidRequestBody, ExecuteProofRequestBody, FulfillProofRequestBody, RequestProofRequestBody,
        SettleRequestBody,
    };
    use std::str::FromStr;

    #[test]
    fn test_verify_request_proof_signature() {
        // Fixture data
        let message_hex = "0801122000000000000000000000000000000000000000000000000000000000000000001a0a7370312d76332e302e3020022803324973333a2f2f73706e2d6172746966616374732d70726f64756374696f6e332f737464696e732f61727469666163745f30316a716367746a72376573383833616d6b78333073716b673938e80740e80748904e";
        let sender_hex = "31f8dc299e8e473f6562be20c047efbb93b8f3b3";
        let signature_hex = "0861fc247bbb6ab7aa9fd9b8e199bca8fea2e448103d8995ce2f4c3bd1bbe9035b17c7655f8d1b8e6256f12a4e9f45289d8ffc55b66d0c5982489502801cb8611c";

        // Decode the message to get the RequestProofRequestBody
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = RequestProofRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Ensure the encoded body matches the original message
        let mut buf = Vec::new();
        decoded_body.encode(&mut buf).unwrap();
        assert_eq!(hex::encode(buf), message_hex);

        // Verify the request proof with the new function
        let signature = hex::decode(signature_hex).unwrap();
        let result = proto_verify(&decoded_body, &signature);

        // Check if verification passed
        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());

        // Verify that the recovered signer matches expected address
        let recovered_signer = result.unwrap();
        let expected_address = Address::from_str(sender_hex).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_bid_request_signature() {
        // Fixture data
        let message_hex = "1220a3ac34d4d49db9984ec3e96578503591eb414edcd9c4f6fb865a8f6f8d81937a";
        let sender_hex = "d7cfc5088b9ad010bffa295ff89bc472a7e8ddee";
        let signature_hex = "87c923b7a44f7768fa2ab1b8ed821be5fd2339fed6694ea788d335a4968719db3bd5334d74d15861364a947dd11642bc0550774f063fed3a59cc331ddf95531e1b";

        // Decode the message to get the BidRequestBody
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = BidRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Verify signature
        let signature = hex::decode(signature_hex).unwrap();
        let result = proto_verify(&decoded_body, &signature);

        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());
        let recovered_signer = result.unwrap();
        let expected_address = Address::from_str(sender_hex).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_settle_request_signature() {
        // Fixture data
        let message_hex = "1220a3ac34d4d49db9984ec3e96578503591eb414edcd9c4f6fb865a8f6f8d81937a";
        let sender_hex = "190c45613465c349bae30f8eb5fb7d3ee2ad698c";
        let signature_hex = "a80cb93068cd2aaa521ac84a3b0bb1b53fa313954bee9ca8b5ad4a7fa1f940806d45c115be493e185301db1d311ef3071b57375dffb02a16bf9c37a3059541701b";

        // Decode the message to get the SettleRequestBody
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = SettleRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Verify signature
        let signature = hex::decode(signature_hex).unwrap();
        let result = proto_verify(&decoded_body, &signature);

        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());
        let recovered_signer = result.unwrap();
        let expected_address = Address::from_str(sender_hex).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_execute_proof_request_signature() {
        // Fixture data
        let message_hex = "089b0212203ad3bb08bb53eaa7227e55c99311b61f570a201ff19e985512d1213db0f7d4e918022220c0a9dffe36892d12d9516056f57883abf69985dc29efda572714c61b184aca7b28c4a4fe6d30f3d9ca9f01";
        let sender_hex = "29cf94C0809Bac6DFC837B5DA92D0c7F088E7Da1";
        let signature_hex = "c8a00ba5a55e4b248f0165e4a28f4cb80366078e66a7e17417542c8edc1644155e5c0a720cf73e2ffcd559d52b2511494831101d70fdc7aeaa5a63c47daaba6a1b";

        // Decode the message to get the ExecuteProofRequestBody
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = ExecuteProofRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Verify signature
        let signature = hex::decode(signature_hex).unwrap();
        // Remove the 0x prefix if present
        let signature = if let Some(stripped) = signature_hex.strip_prefix("0x") {
            hex::decode(stripped).unwrap()
        } else {
            signature
        };

        let result = proto_verify(&decoded_body, &signature);

        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());
        let recovered_signer = result.unwrap();
        // Handle case-insensitive comparison for Ethereum addresses
        let expected_address = Address::from_str(&sender_hex.to_lowercase()).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }

    #[test]
    fn test_verify_fulfill_proof_request_signature() {
        // Fixture data
        let message_hex = "08011220a3ac34d4d49db9984ec3e96578503591eb414edcd9c4f6fb865a8f6f8d81937a1a6400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        let sender_hex = "b58e45afb431fa82de4d3f6e963bd805f96141ab";
        let signature_hex = "4df69585c0f084482af1f477289e3ae38158d42ba43886085696f2f28dbad84e34bc763d4278f006d55ecd56e750772b3e1d7b7756159c1dbbcaa760d80ce7231c";

        // Decode the message to get the FulfillProofRequestBody
        let message_bytes = hex::decode(message_hex).unwrap();
        let decoded_body = FulfillProofRequestBody::decode(message_bytes.as_slice()).unwrap();

        // Verify signature
        let signature = hex::decode(signature_hex).unwrap();
        let result = proto_verify(&decoded_body, &signature);

        assert!(result.is_ok(), "Signature verification failed: {:?}", result.err());
        let recovered_signer = result.unwrap();
        let expected_address = Address::from_str(sender_hex).unwrap();
        assert_eq!(recovered_signer, expected_address);
    }
}
