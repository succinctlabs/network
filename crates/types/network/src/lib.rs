#[rustfmt::skip]
mod network;
pub use network::*;

#[rustfmt::skip]
mod types;
pub use types::*;

use alloy_primitives::Keccak256;
use alloy::primitives::PrimitiveSignature;
use alloy_signer::SignerSync;
use prost::Message;
pub use serde::{Deserialize, Serialize};
pub use types::*;

pub trait Signable: Message {
    fn sign<S: SignerSync>(&self, signer: &S) -> PrimitiveSignature;
}

impl<T: Message> Signable for T {
    fn sign<S: SignerSync>(&self, signer: &S) -> PrimitiveSignature {
        signer.sign_message_sync(&self.encode_to_vec()).unwrap()
    }
}

pub trait HashableWithSender: Message {
    fn hash_with_signer(&self, sender: &[u8]) -> Result<[u8; 32], prost::EncodeError>;
}

impl<T: Message> HashableWithSender for T {
    fn hash_with_signer(&self, sender: &[u8]) -> Result<[u8; 32], prost::EncodeError> {
        let mut data = Vec::new();
        data.extend_from_slice(sender);
        self.encode(&mut data)?;

        let mut hasher = Keccak256::new();
        hasher.update(&data);
        Ok(hasher.finalize().into())
    }
}