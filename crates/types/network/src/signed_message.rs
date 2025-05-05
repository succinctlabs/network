#[allow(deprecated)]
use alloy::primitives::{Address, Signature};
#[allow(unused_imports)]
use prost::Message;
use thiserror::Error;

use crate::{
    AcceptDelegationRequest, AddCreditRequest, AddDelegationRequest, AddReservationRequest,
    BetRequest, BidRequest, ClaimGpuRequest, CompleteOnboardingRequest, ConnectTwitterRequest,
    CreateProgramRequest, ExecuteProofRequest, FailExecutionRequest, FailFulfillmentRequest,
    FulfillProofRequest, LinkWhitelistedDiscordRequest, LinkWhitelistedGithubRequest,
    LinkWhitelistedTwitterRequest, MessageFormat, ProcessClicksRequest, PurchaseUpgradeRequest,
    RedeemCodeRequest, RedeemStarsRequest, RemoveDelegationRequest, RemoveReservationRequest,
    RequestProofRequest, RequestRandomProofRequest, RetrieveProvingKeyRequest,
    Set2048HighScoreRequest, SetAccountNameRequest, SetCoinCrazeHighScoreRequest,
    SetFlowHighScoreRequest, SetGpuCoordinatesRequest, SetGpuDelegateRequest, SetGpuVariantRequest,
    SetLeanHighScoreRequest, SetProgramNameRequest, SetTermsSignatureRequest,
    SetTurboHighScoreRequest, SetTurboTimeTrialHighScoreRequest, SetUseTwitterHandleRequest,
    SetUseTwitterImageRequest, SetVolleyballHighScoreRequest, SettleRequest,
    SubmitCaptchaGameRequest, SubmitEthBlockMetadataRequest, SubmitQuizGameRequest,
    TerminateDelegationRequest,
};

use crate::json::{format_json_message, JsonFormatError};

pub trait SignedMessage {
    fn signature(&self) -> Vec<u8>;
    fn nonce(&self) -> Result<u64, MessageError>;
    fn message(&self) -> Result<Vec<u8>, MessageError>;
    fn recover_sender(&self) -> Result<(Address, Vec<u8>), RecoverSenderError>;
}

#[derive(Error, Debug)]
pub enum MessageError {
    #[error("Empty message")]
    EmptyMessage,
    #[error("JSON error: {0}")]
    JsonError(String),
    #[error("Binary error: {0}")]
    BinaryError(String),
}

#[derive(Error, Debug)]
pub enum RecoverSenderError {
    #[error("Failed to deserialize signature: {0}")]
    SignatureDeserializationError(String),
    #[error("Empty message")]
    EmptyMessage,
    #[error("Failed to recover address: {0}")]
    AddressRecoveryError(String),
}

macro_rules! impl_signed_message {
    ($type:ty) => {
        impl SignedMessage for $type {
            fn signature(&self) -> Vec<u8> {
                self.signature.clone()
            }

            fn nonce(&self) -> Result<u64, MessageError> {
                match &self.body {
                    Some(body) => Ok(body.nonce as u64),
                    None => Err(MessageError::EmptyMessage),
                }
            }

            fn message(&self) -> Result<Vec<u8>, MessageError> {
                let format = MessageFormat::try_from(self.format).unwrap_or(MessageFormat::Binary);

                match &self.body {
                    Some(body) => match format {
                        MessageFormat::Json => format_json_message(body).map_err(|e| match e {
                            JsonFormatError::SerializationError(msg) => {
                                MessageError::JsonError(msg)
                            }
                        }),
                        MessageFormat::Binary => {
                            let proto_bytes = body.encode_to_vec();
                            Ok(proto_bytes)
                        }
                        MessageFormat::UnspecifiedMessageFormat => {
                            let proto_bytes = body.encode_to_vec();
                            Ok(proto_bytes)
                        }
                    },
                    None => Err(MessageError::EmptyMessage),
                }
            }

            fn recover_sender(&self) -> Result<(Address, Vec<u8>), RecoverSenderError> {
                let message = self.message().map_err(|_| RecoverSenderError::EmptyMessage)?;
                let sender = recover_sender_raw(&self.signature, &message)?;
                Ok((sender, message))
            }
        }
    };
}

impl_signed_message!(RequestProofRequest);
impl_signed_message!(RequestRandomProofRequest);
impl_signed_message!(FulfillProofRequest);
impl_signed_message!(ExecuteProofRequest);
impl_signed_message!(FailFulfillmentRequest);
impl_signed_message!(FailExecutionRequest);
impl_signed_message!(AddDelegationRequest);
impl_signed_message!(RemoveDelegationRequest);
impl_signed_message!(TerminateDelegationRequest);
impl_signed_message!(AcceptDelegationRequest);
impl_signed_message!(SetAccountNameRequest);
impl_signed_message!(CreateProgramRequest);
impl_signed_message!(SetProgramNameRequest);
impl_signed_message!(AddCreditRequest);
impl_signed_message!(AddReservationRequest);
impl_signed_message!(RemoveReservationRequest);
impl_signed_message!(BidRequest);
impl_signed_message!(SettleRequest);
impl_signed_message!(SetTermsSignatureRequest);
impl_signed_message!(RedeemCodeRequest);
impl_signed_message!(ConnectTwitterRequest);
impl_signed_message!(CompleteOnboardingRequest);
impl_signed_message!(SetUseTwitterHandleRequest);
impl_signed_message!(SetUseTwitterImageRequest);
impl_signed_message!(SubmitCaptchaGameRequest);
impl_signed_message!(RedeemStarsRequest);
impl_signed_message!(SetTurboHighScoreRequest);
impl_signed_message!(SubmitQuizGameRequest);
impl_signed_message!(SubmitEthBlockMetadataRequest);
impl_signed_message!(SetGpuDelegateRequest);
impl_signed_message!(Set2048HighScoreRequest);
impl_signed_message!(ClaimGpuRequest);
impl_signed_message!(SetGpuVariantRequest);
impl_signed_message!(LinkWhitelistedTwitterRequest);
impl_signed_message!(SetVolleyballHighScoreRequest);
impl_signed_message!(RetrieveProvingKeyRequest);
impl_signed_message!(LinkWhitelistedGithubRequest);
impl_signed_message!(LinkWhitelistedDiscordRequest);
impl_signed_message!(SetTurboTimeTrialHighScoreRequest);
impl_signed_message!(SetCoinCrazeHighScoreRequest);
impl_signed_message!(SetGpuCoordinatesRequest);
impl_signed_message!(SetLeanHighScoreRequest);
impl_signed_message!(ProcessClicksRequest);
impl_signed_message!(PurchaseUpgradeRequest);
impl_signed_message!(BetRequest);
impl_signed_message!(SetFlowHighScoreRequest);

pub fn recover_sender_raw(signature: &[u8], message: &[u8]) -> Result<Address, RecoverSenderError> {
    #[allow(deprecated)]
    let signature = Signature::try_from(signature)
        .map_err(|e| RecoverSenderError::SignatureDeserializationError(e.to_string()))?;

    signature
        .recover_address_from_msg(message)
        .map_err(|e| RecoverSenderError::AddressRecoveryError(e.to_string()))
}
