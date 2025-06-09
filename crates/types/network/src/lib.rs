#[rustfmt::skip]
mod network;
#[rustfmt::skip]
mod types;

use alloy::primitives::PrimitiveSignature;
use alloy_signer::SignerSync;
pub use network::*;
use prost::Message;
pub use serde::{Deserialize, Serialize};

pub trait Signable: Message {
    fn sign<S: SignerSync>(&self, signer: &S) -> PrimitiveSignature;
}

impl<T: Message> Signable for T {
    fn sign<S: SignerSync>(&self, signer: &S) -> PrimitiveSignature {
        signer.sign_message_sync(&self.encode_to_vec()).unwrap()
    }
}
