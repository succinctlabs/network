//! Receipts.
//!
//! This module contains the types for receipts that are emitted from the vApp.

use alloy_sol_types::SolValue;
use serde::{Deserialize, Serialize};

use crate::{
    errors::VAppRevert,
    sol::{CreateProver, Deposit, Receipt, TransactionStatus, TransactionVariant, Withdraw},
};

/// Result of executing a vApp transaction.
pub enum VAppExecutionResult {
    /// Transaction execution succeeded, optionally producing a receipt.
    Success(Option<VAppReceipt>),
    /// Transaction execution reverted, optionally producing a receipt.
    Revert((Option<VAppReceipt>, VAppRevert)),
}

/// `VApp` Receipts represent the succesful execution of a [`crate::transactions::VAppTransaction`].
///
/// These receipts are used to invoke follow up transactions on the settlement contract.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum VAppReceipt {
    /// A receipt for a [`crate::transactions::VAppTransaction::Deposit`] transaction.
    Deposit(OnchainReceipt<Deposit>),
    /// A receipt for a [`crate::transactions::VAppTransaction::Withdraw`] transaction.
    Withdraw(OnchainReceipt<Withdraw>),
    /// A receipt for a [`crate::transactions::VAppTransaction::CreateProver`] transaction.
    CreateProver(OnchainReceipt<CreateProver>),
}

/// Generic receipt structure for transactions included in the ledger from the settlement contract.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OnchainReceipt<T> {
    /// The onchain transaction ID.
    pub onchain_tx_id: u64,
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
            VAppReceipt::Withdraw(receipt) => Receipt {
                variant: TransactionVariant::Withdraw,
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
        }
    }
}
