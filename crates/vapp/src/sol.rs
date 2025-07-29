//! Solidity types.
//!
//! This module contains the types for the Solidity contracts that are used by the vApp.

use alloy_primitives::{Address, U256};
use alloy_sol_types::sol;
use serde::{Deserialize, Serialize};

use crate::{errors::VAppPanic, u256};

sol! {
    /// @notice A transaction.
    #[derive(Debug)]
    struct Transaction {
        /// @notice The variant of the transaction.
        TransactionVariant variant;
        /// @notice The status of the transaction.
        TransactionStatus status;
        /// @notice The onchain transaction ID.
        uint64 onchainTxId;
        /// @notice The action of one of {Deposit, Withdraw, CreateProver}.
        bytes action;
    }

    /// @notice The receipt for a transaction.
    #[derive(Debug)]
    struct Receipt {
        /// @notice The variant of the transaction.
        TransactionVariant variant;
        /// @notice The status of the transaction.
        TransactionStatus status;
        /// @notice The onchain transaction ID.
        uint64 onchainTxId;
        /// @notice The action of one of {Deposit, Withdraw, CreateProver}.
        bytes action;
    }

    /// @notice The type of transaction.
    #[derive(Debug)]
    enum TransactionVariant {
        /// @notice The variant for a deposit transaction.
        Deposit,
        /// @notice The variant for a withdraw transaction.
        Withdraw,
        /// @notice The variant for a create prover transaction.
        CreateProver
    }

    /// @notice The status of a transaction.
    #[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
    enum TransactionStatus {
        /// The transaction has no initialiezd status.
        None,
        /// The transaction has been included in the ledger but is not yet executed.
        Pending,
        /// The transaction executed successfully.
        Completed,
        /// The transaction reverted during execution.
        Reverted
    }

    /// @notice The action data for a deposit.
    #[derive(Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
    struct Deposit {
        address account;
        uint256 amount;
    }

    /// @notice The action data for a withdraw.
    #[derive(Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
    struct Withdraw {
        address account;
        uint256 amount;
    }

    /// @notice The action data for an add signer.
    #[derive(Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
    struct CreateProver {
        address prover;
        address owner;
        uint256 stakerFeeBips;
    }

    /// @notice The public values encoded as a struct that can be easily deserialized inside Solidity.
    #[derive(Debug)]
    struct StepPublicValues {
        bytes32 oldRoot;
        bytes32 newRoot;
        uint64 timestamp;
        Receipt[] receipts;
    }

    /// @notice The state of the VApp.
    #[derive(Debug, Default, PartialEq, Serialize, Deserialize)]
    struct VAppStateContainer {
        bytes32 domain;
        uint64 txId;
        uint64 onchainTxId;
        uint64 onchainBlock;
        uint64 onchainLogIndex;
        bytes32 accountsRoot;
        bytes32 transactionsRoot;
    }

    /// @notice The account data for Merkle tree leaves.
    #[derive(Debug, Default, PartialEq, Serialize, Deserialize)]
    struct Account {
        uint256 balance;
        address owner;
        address delegatedSigner;
        uint256 stakerFeeBips;
    }

    /// @notice Emitted when a receipt is pending.
    event TransactionPending(
        uint64 indexed onchainTxId, TransactionVariant indexed variant, bytes data
    );
}

impl Account {
    /// Returns the balance of the account.
    #[must_use]
    pub fn get_balance(&self) -> U256 {
        self.balance
    }

    /// Adds an amount to the balance of the account.
    pub fn add_balance(&mut self, amount: U256) -> Result<(), VAppPanic> {
        self.balance = u256::add(self.balance, amount)?;
        Ok(())
    }

    /// Removes an amount from the balance of the account.
    pub fn deduct_balance(&mut self, amount: U256) -> Result<(), VAppPanic> {
        self.balance = u256::sub(self.balance, amount)?;
        Ok(())
    }

    /// Set the owner of the account.
    pub fn set_owner(&mut self, owner: Address) -> &mut Self {
        self.owner = owner;
        self
    }

    /// Get the owner of the account.
    #[must_use]
    pub fn get_owner(&self) -> Address {
        self.owner
    }

    /// Checks whether the signer is the delegated signer of the account.
    #[must_use]
    pub fn is_signer(&self, signer: Address) -> bool {
        self.delegatedSigner == signer
    }

    /// Get the delegated signer of the account.
    #[must_use]
    pub fn get_signer(&self) -> Address {
        self.delegatedSigner
    }

    /// Set the delegated signer for the account.
    pub fn set_signer(&mut self, signer: Address) -> &mut Self {
        self.delegatedSigner = signer;
        self
    }

    /// Remove the delegated signer from the account.
    pub fn remove_signer(&mut self, _signer: Address) {
        self.delegatedSigner = Address::ZERO;
    }

    /// Get the staker fee in basis points.
    #[must_use]
    pub fn get_staker_fee_bips(&self) -> U256 {
        self.stakerFeeBips
    }

    /// Set the staker fee in basis points.
    pub fn set_staker_fee_bips(&mut self, staker_fee_bips: U256) -> &mut Self {
        self.stakerFeeBips = staker_fee_bips;
        self
    }
}
