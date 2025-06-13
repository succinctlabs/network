//! Verifier.
//!
//! This module contains the traits and implementations for proof verifiers in the vApp.

use thiserror::Error;

/// Errors that can occur during proof verification.
#[derive(Error, Debug)]
#[allow(missing_docs)]
pub enum VAppVerifierError {
    #[error("invalid proof")]
    InvalidProof,
}

/// A trait for verifying proofs.
pub trait VAppVerifier: Default + Send + Sync {
    /// Verifies a proof.
    fn verify(
        &self,
        vk_digest_array: [u32; 8],
        pv_digest_array: [u8; 32],
    ) -> Result<(), VAppVerifierError>;
}

/// A mock verifier for testing.
#[derive(Debug, Clone, Default)]
pub struct MockVerifier;

impl VAppVerifier for MockVerifier {
    fn verify(
        &self,
        _vk_digest_array: [u32; 8],
        _pv_digest_array: [u8; 32],
    ) -> Result<(), VAppVerifierError> {
        Ok(())
    }
}

/// A reject verifier for testing.
#[derive(Debug, Clone, Default)]
pub struct RejectVerifier;

impl VAppVerifier for RejectVerifier {
    fn verify(
        &self,
        _vk_digest_array: [u32; 8],
        _pv_digest_array: [u8; 32],
    ) -> Result<(), VAppVerifierError> {
        Err(VAppVerifierError::InvalidProof)
    }
}
