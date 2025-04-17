#[rustfmt::skip]
mod network;
pub mod json;
pub mod signed_message;

use alloy::primitives::{Address, Signature, TxHash, U256};
use alloy_signer::SignerSync;
pub use network::*;
use prost::Message;
pub use serde::{Deserialize, Serialize};
pub trait Signable: Message {
    fn sign<S: SignerSync>(&self, signer: &S) -> Signature;
}

impl<T: Message> Signable for T {
    fn sign<S: SignerSync>(&self, signer: &S) -> Signature {
        signer.sign_message_sync(&self.encode_to_vec()).unwrap()
    }
}

pub struct Deposit {
    pub from: Address,
    pub amount: U256,
    pub block_number: u64,
    pub log_index: u64,
    pub tx_hash: TxHash,
}

pub struct Withdrawal {
    pub to: Address,
    pub amount: U256,
    pub block_number: u64,
    pub log_index: u64,
    pub tx_hash: TxHash,
}

pub struct Minted {
    pub to: Address,
    pub token_id: u64,
    pub stage: i32,
    pub block_number: u64,
    pub log_index: u64,
    pub tx_hash: TxHash,
}
