use alloy_primitives::{Address, B256, U256};
use std::error::Error as StdError;
use thiserror::Error;

/// The error that can occur during a state transition of the vApp.
///
/// These errors are typically produced via the `VAppState::execute` method.
#[derive(Debug)]
pub enum VAppError {
    /// Recoverable errors.
    Revert(VAppRevert),
    /// Unrecoverable errors.
    Panic(VAppPanic),
}

/// A recoverable error that will be recorded in the ledger.
#[derive(Debug, Error, PartialEq)]
pub enum VAppRevert {
    #[error("Insufficient balance for withdrawal: {account}: {amount} > {balance}")]
    InsufficientBalanceForWithdrawal { account: Address, amount: U256, balance: U256 },

    #[error("Account does not exist: {account}")]
    AccountDoesNotExist { account: Address },
}

/// An unrecoverable error that will prevent a transaction from being included in the ledger.
#[derive(Debug, Error, PartialEq)]
pub enum VAppPanic {
    #[error("EIP-712 domain already initialized")]
    Eip712DomainAlreadyInitialized,

    #[error("Out of order receipt {expected} != {actual}")]
    ReceiptOutOfOrder { expected: u64, actual: u64 },

    #[error("Out of order block number {expected} != {actual}")]
    BlockNumberOutOfOrder { expected: u64, actual: u64 },

    #[error("Out of order log index: {current} >= {next}")]
    LogIndexOutOfOrder { current: u64, next: u64 },

    #[error("Insufficient balance for account {account}: {amount} > {balance}")]
    InsufficientBalance { account: Address, amount: U256, balance: U256 },

    #[error("Invalid proto signature for request in clear")]
    InvalidRequestSignature,

    #[error("Invalid proto signature for bid in clear")]
    InvalidBidSignature,

    #[error("Invalid proto signature for settle in clear")]
    InvalidSettleSignature,

    #[error("Invalid proto signature for fulfill in clear")]
    InvalidFulfillSignature,

    #[error("Invalid proto signature for execute in clear")]
    InvalidExecuteSignature,

    #[error("Invalid proto signature for transfer")]
    InvalidTransferSignature,

    #[error("Missing proto body")]
    MissingProtoBody,

    #[error("Invalid proto signature for delegation")]
    InvalidDelegationSignature,

    #[error("Only owner can delegate")]
    OnlyOwnerCanDelegate,

    #[error("Request id mismatch in clear")]
    RequestIdMismatch {
        request_id: Address,
        bid_request_id: Address,
        settle_request_id: Address,
        execute_request_id: Address,
        fulfill_request_id: Address,
    },

    #[error("Invalid bid amount in clear: {amount}")]
    InvalidBidAmount { amount: String },

    #[error("Missing gas used in execute in clear")]
    MissingGasUsed,

    #[error("Gas limit exceeded in execute in clear")]
    GasLimitExceeded { gas_used: u64, gas_limit: u64 },

    #[error("Invalid account")]
    InvalidAccount,

    #[error("Requester can't afford the cost of the proof: {account}: {amount} > {balance}")]
    RequesterBalanceTooLow { account: Address, amount: U256, balance: U256 },

    #[error("Prover not in whitelist")]
    ProverNotInWhitelist { prover: Address },

    #[error("Execution failed")]
    ExecutionFailed { status: i32 },

    #[error("Request already consumed for address {address}: {nonce}")]
    RequestAlreadyConsumed { address: Address, nonce: u64 },

    #[error("Invalid proof mode: {mode}")]
    InvalidProofMode { mode: i32 },

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

    #[error("Auctioneer mismatch: request_auctioneer={request_auctioneer}, settle_signer={settle_signer}, auctioneer={auctioneer}")]
    AuctioneerMismatch { request_auctioneer: Address, settle_signer: Address, auctioneer: Address },

    #[error("Executor mismatch: request_executor={request_executor}, execute_signer={execute_signer}, executor={executor}")]
    ExecutorMismatch { request_executor: Address, execute_signer: Address, executor: Address },

    #[error("Address deserialization failed")]
    AddressDeserializationFailed,

    #[error("Domain deserialization failed")]
    DomainDeserializationFailed,

    #[error("Invalid verifier signature")]
    InvalidVerifierSignature,

    #[error("Hashing body failed")]
    HashingBodyFailed,
}

impl From<VAppRevert> for VAppError {
    fn from(err: VAppRevert) -> Self {
        VAppError::Revert(err)
    }
}

impl From<VAppPanic> for VAppError {
    fn from(err: VAppPanic) -> Self {
        VAppError::Panic(err)
    }
}

impl StdError for VAppError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            VAppError::Revert(err) => Some(err),
            VAppError::Panic(err) => Some(err),
        }
    }
}

impl std::fmt::Display for VAppError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            VAppError::Revert(err) => write!(f, "VApp revert: {}", err),
            VAppError::Panic(err) => write!(f, "VApp panic: {}", err),
        }
    }
}
