//! Execute message layout consumed by the v1.3.0 STF ELF.
//!
//! Field order determines the bincode layout. Protobuf tags and JSON field names determine the
//! signing bytes the guest reconstructs from the body.

use eyre::{bail, ensure, Result};
use prost::Message;
use serde::{Deserialize, Serialize};
use spn_network_types::{ExecuteFailureCause, ExecutionStatus, MessageFormat, TransactionVariant};

use crate::signing::signing_bytes;

/// Signed execute request in a v1.3.0 clear transaction.
#[derive(Clone, PartialEq, Eq, Message, Serialize, Deserialize)]
pub struct ExecuteProofRequest {
    /// Encoding used to sign the body.
    #[prost(enumeration = "MessageFormat", tag = "1")]
    pub format: i32,
    /// Executor's signature over the encoded body.
    #[prost(bytes = "vec", tag = "2")]
    pub signature: Vec<u8>,
    /// Execution result supplied to the guest.
    #[prost(message, optional, tag = "3")]
    pub body: Option<ExecuteProofRequestBody>,
}

/// Fields signed by the executor and consumed by the v1.3.0 STF.
#[derive(Clone, PartialEq, Eq, Message, Serialize, Deserialize)]
pub struct ExecuteProofRequestBody {
    /// Executor's account nonce.
    #[prost(uint64, tag = "1")]
    pub nonce: u64,
    /// Identifier of the proof request.
    #[prost(bytes = "vec", tag = "2")]
    pub request_id: Vec<u8>,
    /// Execution status reported by the executor.
    #[prost(enumeration = "ExecutionStatus", tag = "3")]
    pub execution_status: i32,
    /// Hash of the execution's public values.
    #[prost(bytes = "vec", optional, tag = "4")]
    pub public_values_hash: Option<Vec<u8>>,
    /// Cycles used by the execution.
    #[prost(uint64, optional, tag = "5")]
    pub cycles: Option<u64>,
    /// Gas used by the execution.
    #[prost(uint64, optional, tag = "6")]
    pub pgus: Option<u64>,
    /// Signing domain of the proof request.
    #[prost(bytes = "vec", tag = "7")]
    pub domain: Vec<u8>,
    /// Amount charged for an unexecutable request.
    #[prost(string, optional, tag = "8")]
    pub punishment: Option<String>,
    /// Cause of an execution failure.
    #[prost(enumeration = "ExecuteFailureCause", optional, tag = "9")]
    pub failure_cause: Option<i32>,
    /// Transaction variant signed by the executor.
    #[prost(enumeration = "TransactionVariant", tag = "10")]
    pub variant: i32,
}

impl ExecuteProofRequest {
    /// Constructs the guest input from the original signed body. The STF verifies the signature.
    ///
    /// # Errors
    ///
    /// Returns an error if the format is unsupported, the body cannot be decoded, or the guest
    /// would reconstruct different signing bytes.
    pub fn from_signed_body(
        format: MessageFormat,
        signature: Vec<u8>,
        signed_body: &[u8],
    ) -> Result<Self> {
        let body = match format {
            MessageFormat::Binary => ExecuteProofRequestBody::decode(signed_body)?,
            MessageFormat::Json => serde_json::from_slice(signed_body)?,
            MessageFormat::UnspecifiedMessageFormat => bail!("unspecified execute message format"),
        };
        ensure!(
            signing_bytes(&body, format)? == signed_body,
            "v1.3.0 STF cannot reproduce the signed execute body"
        );
        Ok(Self { format: format.into(), signature, body: Some(body) })
    }
}
