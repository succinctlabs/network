//! Receipts.
//!
//! This module contains the types for receipts that are emitted from the vApp.

use alloy_sol_types::SolValue;
use serde::{Deserialize, Serialize};

use crate::sol::{CreateProver, Deposit, Receipt, TransactionStatus, TransactionVariant, Withdraw};

/// `VApp` Receipts represent the succesful execution of a [`crate::transactions::VAppTransaction`].
///
/// These receipts are used to invoke follow up transactions on the settlement contract.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum VAppReceipt {
    /// A receipt for a [`crate::transactions::VAppTransaction::Deposit`] transaction.
    Deposit(OnchainReceipt<Deposit>),
    /// A receipt for a [`crate::transactions::VAppTransaction::CreateProver`] transaction.
    CreateProver(OnchainReceipt<CreateProver>),
    /// A receipt for a [`crate::transactions::VAppTransaction::Withdraw`] transaction.
    Withdraw(OffchainReceipt<Withdraw>),
}

/// Onchain receipts are produced by transactions included in the ledger from the settlement contract.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OnchainReceipt<T> {
    /// The onchain transaction ID.
    pub onchain_tx_id: u64,
    /// The status of the transaction.
    pub status: TransactionStatus,
    /// The action data for the transaction.
    pub action: T,
}

/// Offchain receipts are produced by transactions that are included by the auctioneer.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OffchainReceipt<T> {
    /// The status of the transaction.
    pub status: TransactionStatus,
    /// The action data for the transaction.
    pub action: T,
}

impl VAppReceipt {
    /// Converts the [`VAppReceipt`] to a [Receipt] struct for onchain interaction and verification.
    #[must_use]
    pub fn sol(&self) -> Receipt {
        match self {
            VAppReceipt::Deposit(receipt) => Receipt {
                variant: TransactionVariant::Deposit,
                status: receipt.status,
                onchainTxId: receipt.onchain_tx_id,
                action: receipt.action.abi_encode().into(),
            },
            VAppReceipt::CreateProver(receipt) => Receipt {
                variant: TransactionVariant::CreateProver,
                status: receipt.status,
                onchainTxId: receipt.onchain_tx_id,
                action: receipt.action.abi_encode().into(),
            },
            VAppReceipt::Withdraw(receipt) => Receipt {
                variant: TransactionVariant::Withdraw,
                status: receipt.status,
                onchainTxId: u64::MAX,
                action: receipt.action.abi_encode().into(),
            },
        }
    }
}
