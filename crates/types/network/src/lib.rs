#[cfg(feature = "network")]
#[rustfmt::skip]
mod network;

#[cfg(feature = "network")]
pub use network::*;

#[rustfmt::skip]
mod types;
pub use types::*;

use alloy_primitives::Keccak256;
#[cfg(feature = "network")]
use alloy_primitives::Signature;
#[cfg(feature = "network")]
use alloy_signer::SignerSync;
use prost::Message;

#[cfg(feature = "network")]
pub trait Signable: Message {
    fn sign<S: SignerSync>(&self, signer: &S) -> Signature;
}

#[cfg(feature = "network")]
impl<T: Message> Signable for T {
    fn sign<S: SignerSync>(&self, signer: &S) -> Signature {
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
