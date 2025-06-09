use alloy_primitives::{Address, B256};
use serde::{Deserialize, Serialize};

use crate::{
    merkle::MerkleProof,
    sol::{Account, RequestId},
    sparse::SparseStorage,
    state::VAppState,
    transactions::VAppTransaction,
};

pub mod errors;
pub mod fee;
pub mod helpers;
pub mod merkle;
pub mod receipts;
pub mod signing;
pub mod sol;
pub mod sparse;
pub mod state;
pub mod storage;
pub mod transactions;
pub mod utils;
pub mod verifier;

/// Input structure for the VApp zkVM program.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VAppProgramInput {
    /// The current state root.
    pub root: B256,
    /// The accounts root.
    pub accounts_root: B256,
    /// The requests root.
    pub requests_root: B256,
    /// The current state.
    pub state: VAppState<SparseStorage<Address, Account>, SparseStorage<RequestId, bool>>,
    /// The merkle proofs for account verification.
    pub account_proofs: Vec<MerkleProof<Address, Account>>,
    /// The merkle proofs for request verification.
    pub request_proofs: Vec<MerkleProof<RequestId, bool>>,
    /// The transactions to process.
    pub txs: Vec<(i64, VAppTransaction)>,
    /// The prover's timestamp.
    pub timestamp: u64,
}
