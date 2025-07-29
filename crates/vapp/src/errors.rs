//! Errors.
//!
//! This module contains error types that can be emitted by the crate.

use alloy_primitives::{ruint::ParseError, Address, B256, U256};
use thiserror::Error;

use crate::storage::StorageError;

/// An unrecoverable error that will prevent a transaction from being included in the ledger.
#[derive(Debug, Error, PartialEq)]
#[allow(missing_docs)]
pub enum VAppPanic {
    #[error("Out of order onchain tx {expected} != {actual}")]
    OnchainTxOutOfOrder { expected: u64, actual: u64 },

    #[error("Out of order onchain block {expected} != {actual}")]
    BlockNumberOutOfOrder { expected: u64, actual: u64 },

    #[error("Out of order onchain log index: {current} >= {next}")]
    LogIndexOutOfOrder { current: u64, next: u64 },

    #[error("Insufficient balance for account {account}: {amount} > {balance}")]
    InsufficientBalance { account: Address, amount: U256, balance: U256 },

    #[error("Invalid message format")]
    InvalidMessageFormat,

    #[error("Failed to serialize message: {format}")]
    FailedToSerializeMessage { format: i32, error: String },

    #[error("Invalid signature: {error}")]
    InvalidSignature { error: String },

    #[error("Missing proto body")]
    MissingProtoBody,

    #[error("Only owner can delegate")]
    OnlyOwnerCanDelegate,

    #[error("Request id mismatch in clear")]
    RequestIdMismatch { found: Vec<u8>, expected: Vec<u8> },

    #[error("Invalid bid amount in clear: {amount}")]
    InvalidU256Amount { amount: String },

    #[error("Missing gas used in execute in clear")]
    MissingPgusUsed,

    #[error("Gas limit exceeded in execute in clear")]
    GasLimitExceeded { pgus: U256, gas_limit: U256 },

    #[error("Account does not exist: {account}")]
    AccountDoesNotExist { account: Address },

    #[error("Prover not in whitelist")]
    ProverNotInWhitelist { prover: Address },

    #[error("Execution failed")]
    ExecutionFailed { status: i32 },

    #[error("Request already consumed: {id}")]
    TransactionAlreadyProcessed { id: String },

    #[error("Unsupported proof mode: {mode}")]
    UnsupportedProofMode { mode: i32 },

    #[error("Invalid proof")]
    InvalidProof,

    #[error("Invalid transfer amount: {amount}")]
    InvalidTransferAmount { amount: String },

    #[error("Domain mismatch: {expected} != {actual}")]
    DomainMismatch { expected: B256, actual: B256 },

    #[error(
        "Prover delegated signer mismatch: prover={prover}, delegated_signer={delegated_signer}"
    )]
    ProverDelegatedSignerMismatch { prover: Address, delegated_signer: Address },

    #[error("Auctioneer mismatch: request_auctioneer={request_auctioneer}, settle_signer={settle_signer}")]
    AuctioneerMismatch { request_auctioneer: Address, settle_signer: Address },

    #[error(
        "Executor mismatch: request_executor={request_executor}, execute_signer={execute_signer}"
    )]
    ExecutorMismatch { request_executor: Address, execute_signer: Address },

    #[error("Address deserialization failed")]
    AddressDeserializationFailed,

    #[error("Domain deserialization failed")]
    DomainDeserializationFailed,

    #[error("Invalid verifier signature")]
    InvalidVerifierSignature,

    #[error("Hashing body failed")]
    HashingBodyFailed,

    #[error("Failed to parse hash")]
    FailedToParseBytes,

    #[error("Missing public values hash")]
    MissingPublicValuesHash,

    #[error("Max price per pgu exceeded: {max_price_per_pgu} > {price}")]
    MaxPricePerPguExceeded { max_price_per_pgu: U256, price: U256 },

    #[error("Parse error: {0}")]
    U256ParseError(#[from] ParseError),

    #[error("Missing fulfill field in clear transaction")]
    MissingFulfill,

    #[error("Missing verifier signature in clear transaction")]
    MissingVerifierSignature,

    #[error("Missing punishment value in execute response")]
    MissingPunishment,

    #[error("Punishment {punishment} exceeds max price {max_price}")]
    PunishmentExceedsMaxCost { punishment: U256, max_price: U256 },

    #[error("Public values hash mismatch")]
    PublicValuesHashMismatch,

    #[error("Prover does not exist: {prover}")]
    ProverDoesNotExist { prover: Address },

    #[error("Protocol fee bips exceeds 100%: {bips}")]
    ProtocolFeeTooHigh { bips: U256 },

    #[error("Staker fee bips exceeds 100%: {bips}")]
    StakerFeeTooHigh { bips: U256 },

    #[error("Sum of protocol and staker fee bips exceeds 100%: {protocol_bips} + {staker_bips}")]
    TotalFeeTooHigh { protocol_bips: U256, staker_bips: U256 },

    #[error("Invalid transaction variant")]
    InvalidTransactionVariant,

    #[error("Storage error: {0}")]
    StorageError(#[from] StorageError),

    #[error("Only the account itself can withdraw since the account is not a prover")]
    OnlyAccountCanWithdraw,

    #[error("Arithmetic overflow")]
    ArithmeticOverflow,
}
