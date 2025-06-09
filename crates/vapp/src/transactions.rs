//! Transactions.
//!
//! This module contains the types for transactions that are executed by the vApp.

use alloy_primitives::B256;
use serde::{Deserialize, Serialize};
use spn_network_types::{
    BidRequest, ExecuteProofRequest, FulfillProofRequest, RequestProofRequest,
    SetDelegationRequest, SettleRequest, TransferRequest,
};

use crate::sol::{CreateProver, Deposit, Withdraw};

/// A transaction that can be executed by the Succinct Prover Network.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[allow(clippy::large_enum_variant)]
pub enum VAppTransaction {
    // Contract (on-chain).
    /// A deposit from the vApp contract.
    ///
    /// The currency of the deposit is the $PROVE token.
    Deposit(OnchainTransaction<Deposit>),

    /// A withdraw from the vApp contract.
    ///
    /// The currency of the withdraw is the $PROVE token.
    Withdraw(OnchainTransaction<Withdraw>),

    /// A set delegated signer from the vApp contract.
    ///
    /// This allows an EOA to sign on the behalf of a prover. Specifically, this EOA can now
    /// bid in proof request auctions using the prover's staked $PROVE.
    CreateProver(OnchainTransaction<CreateProver>),

    // Node (off-chain).
    /// A delegation event from off-chain signed transaction.
    ///
    /// This allows a prover owner to delegate signing authority to another account,
    /// enabling the delegate to bid on proof requests using the prover's staked $PROVE.
    Delegate(DelegateTransaction),

    /// Transfers $PROVE from an account to another.
    Transfer(TransferTransaction),

    /// Clears a proof.
    ///
    /// Verifies the request, bid, assign, execute, and the proof itself. Deducts the request fee
    /// from the requester and transfers proving fees to the prover.
    Clear(ClearTransaction),
}

/// A transaction that was included in the ledger onchain.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OnchainTransaction<T> {
    /// The hash of the transaction.
    pub tx_hash: Option<B256>,
    /// The block number of the transaction.
    pub block: u64,
    /// The log index of the transaction.
    pub log_index: u64,
    /// The onchain transaction ID.
    pub onchain_tx: u64,
    /// The action of the transaction.
    pub action: T,
}

/// A transaction to delegate signing authority to another account.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DelegateTransaction {
    /// The delegation request.
    pub delegation: SetDelegationRequest,
}

/// A transaction to transfer $PROVE from one account to another.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TransferTransaction {
    /// The transfer request.
    pub transfer: TransferRequest,
}

/// A transaction to clear a proof.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClearTransaction {
    /// The request proof request.
    pub request: RequestProofRequest,
    /// The bid request.
    pub bid: BidRequest,
    /// The settle request.
    pub settle: SettleRequest,
    /// The execute proof request.
    pub execute: ExecuteProofRequest,
    /// The fulfill proof request.
    pub fulfill: FulfillProofRequest,
    /// The verify request.
    pub verify: Vec<u8>,
    /// The vk request.
    pub vk: Option<Vec<u8>>,
}
