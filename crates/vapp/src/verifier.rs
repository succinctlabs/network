use thiserror::Error;

#[derive(Error, Debug)]
pub enum VAppVerifierError {
    #[error("invalid proof")]
    InvalidProof,
}

pub trait VAppVerifier: Default + Send + Sync {
    fn verify(
        &self,
        vk_digest_array: [u32; 8],
        pv_digest_array: [u8; 32],
    ) -> Result<(), VAppVerifierError>;
}

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
