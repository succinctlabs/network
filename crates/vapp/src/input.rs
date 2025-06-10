//! Inputs.
//!
//! This module contains types used as inputs into the programs that run inside the SP1 RISC-V zkVM.

use alloy_primitives::{Address, B256};
use serde::{Deserialize, Serialize};

use crate::{
    merkle::MerkleProof, sol::Account, sparse::SparseStorage, state::VAppState, storage::RequestId,
    transactions::VAppTransaction,
};

/// The inputs necessary to prove the state-transition-function of the vApp.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VAppStfInput {
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
