use alloy_sol_types::SolValue;
use serde::{Deserialize, Serialize};

use crate::sol::{CreateProver, Deposit, Receipt, TransactionStatus, TransactionVariant, Withdraw};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum VAppReceipt {
    Deposit(OnchainReceipt<Deposit>),
    Withdraw(OnchainReceipt<Withdraw>),
    CreateProver(OnchainReceipt<CreateProver>),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OnchainReceipt<T> {
    pub onchain_tx_id: u64,
    pub status: TransactionStatus,
    pub action: T,
}

impl VAppReceipt {
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
