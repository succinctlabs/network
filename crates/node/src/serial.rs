use std::{
    panic::{self, AssertUnwindSafe},
    sync::Arc,
};

use alloy_primitives::U256;
use alloy_signer_local::PrivateKeySigner;
use anyhow::Context;
use sp1_sdk::{EnvProver, ProverClient, SP1ProofMode, SP1Stdin};
use spn_artifacts::{Artifact, parse_artifact_id_from_s3_url};
use spn_network_types::{
    BidRequest, BidRequestBody, FulfillProofRequest, FulfillProofRequestBody, FulfillmentStatus,
    GetFilteredProofRequestsRequest, GetNonceRequest, GetProofRequestDetailsRequest, MessageFormat,
    ProofMode, Signable, prover_network_client::ProverNetworkClient,
};
use spn_rpc::{RetryableRpc, fetch_owner};
use spn_utils::{ErrorCapture, time_now};
use tonic::{async_trait, transport::Channel};
use tracing::{debug, error, info};

use crate::{EXPLORER_REQUEST_BASE_URL, NodeBidder, NodeContext, NodeProver, SP1_NETWORK_VERSION};

/// A context that implements [`NodeContext`] for a serial node.
///
/// This context is compatible with both [`SerialBidder`] and [`SerialProver`].
#[derive(Debug, Clone)]
pub struct SerialContext {
    /// The network client for the node.
    pub network: ProverNetworkClient<Channel>,
    /// The signer for the node.
    pub signer: PrivateKeySigner,
}

impl SerialContext {
    /// Create a new [`SerialContext`].
    pub fn new(network: ProverNetworkClient<Channel>, signer: PrivateKeySigner) -> Self {
        Self { network, signer }
    }
}

impl NodeContext for SerialContext {
    fn network(&self) -> &ProverNetworkClient<Channel> {
        &self.network
    }

    fn signer(&self) -> &PrivateKeySigner {
        &self.signer
    }
}

/// A serial bidder.
///
/// This bidder will bid on requests sequentially. It will bid on the first request and then wait
/// for the request to be fulfilled before bidding on the next request. It uses the provided
/// parameters to control how much it bids and how much throughput it can handle.
#[derive(Debug, Clone)]
pub struct SerialBidder {
    /// The bid amount for the bidder.
    pub bid: U256,
    /// The throughput for the bidder.
    pub throughput: f64,
}

impl SerialBidder {
    /// Create a new [`SerialBidder`].
    #[must_use]
    pub fn new(bid: U256, throughput: f64) -> Self {
        Self { bid, throughput }
    }
}

/// A serial prover.
///
/// This prover will generate proofs for requests sequentially using an [`EnvProver`].
pub struct SerialProver {
    /// The underlying prover for the node that will be used to generate proofs.
    prover: Arc<EnvProver>,
    /// The S3 bucket used to fetch artifacts.
    s3_bucket: String,
    /// The S3 region used to fetch artifacts.
    s3_region: String,
}

impl SerialProver {
    /// Create a new [`SerialProver`].
    #[must_use]
    pub fn new(s3_bucket: String, s3_region: String) -> Self {
        Self { prover: Arc::new(ProverClient::from_env()), s3_bucket, s3_region }
    }
}

#[async_trait]
impl<C: NodeContext> NodeBidder<C> for SerialBidder {
    async fn bid(&self, ctx: &C) -> anyhow::Result<()> {
        // Fetch the owner.
        let owner = fetch_owner(ctx.network(), ctx.signer().address().as_ref()).await?;

        // Fetch for open requests.
        let requests = ctx
            .network()
            .clone()
            .get_filtered_proof_requests(GetFilteredProofRequestsRequest {
                version: Some(SP1_NETWORK_VERSION.to_string()),
                fulfillment_status: Some(FulfillmentStatus::Requested.into()),
                minimum_deadline: Some(time_now()),
                limit: Some(1),
                not_bid_by: Some(owner.clone()),
                ..Default::default()
            })
            .await?
            .into_inner()
            .requests;

        // If there are no open requests, return.
        if requests.is_empty() {
            error!("found no auctions to bid in");
            return Ok(());
        }

        // There should only be at most one request.
        if requests.len() > 1 {
            error!("expected 1 request, got {}", requests.len());
            return Ok(());
        }

        let request = requests.first().unwrap();
        let request_id = hex::encode(&request.request_id);
        let address = ctx.signer().address().to_vec();
        ctx.network()
            .clone()
            .with_retry(
                || async {
                    // Get the nonce.
                    let req = GetNonceRequest { address: address.clone() };
                    let nonce = ctx.network().clone().get_nonce(req).await?.into_inner().nonce;

                    // Get request details to access the deadline.
                    let request_details = ctx
                        .network()
                        .clone()
                        .get_proof_request_details(GetProofRequestDetailsRequest {
                            request_id: hex::decode(request_id.clone())?,
                        })
                        .await?
                        .into_inner()
                        .request
                        .ok_or_else(|| anyhow::anyhow!("request details not found"))?;
                    let request_deadline = request_details.deadline;
                    let cycle_limit = request_details.cycle_limit;
                    let current_time = time_now();

                    info!(
                        "📊 Request {}/0x{} - Bid amount: {}, Worst case throughput: {} cycles/sec",
                        EXPLORER_REQUEST_BASE_URL,
                        request_id.clone(),
                        self.bid,
                        self.throughput
                    );

                    // Determine if the bidder should bid on the request.
                    if !should_bid_on_request(
                        self.throughput,
                        request_deadline,
                        cycle_limit,
                        current_time,
                    ) {
                        info!(
                            "Skipping bid for request {}/0x{} due to insufficient time.",
                            EXPLORER_REQUEST_BASE_URL,
                            request_id.clone()
                        );
                        return Ok(());
                    }

                    // Log the bid amount.
                    info!(
                        "Submitting bid with amount: {} for request {}/0x{}",
                        self.bid,
                        EXPLORER_REQUEST_BASE_URL,
                        request_id.clone()
                    );

                    // Create and submit the bid request.
                    let bid_amount = self.bid.to_string();
                    debug!("Sending bid amount in request body: {}", bid_amount);
                    let body = BidRequestBody {
                        nonce,
                        request_id: hex::decode(request_id.clone())
                            .context("failed to decode request_id")?,
                        amount: bid_amount,
                    };
                    let bid_request = BidRequest {
                        format: MessageFormat::Binary.into(),
                        signature: body.sign(&ctx.signer()).into(),
                        body: Some(body),
                    };
                    ctx.network().clone().bid(bid_request).await?;
                    Ok(())
                },
                "bid on request",
            )
            .await?;

        Ok(())
    }
}

#[async_trait]
impl<C: NodeContext> NodeProver<C> for SerialProver {
    #[allow(clippy::too_many_lines)]
    async fn prove(&self, ctx: &C) -> anyhow::Result<()> {
        // Fetch the owner.
        let owner = fetch_owner(ctx.network(), ctx.signer().address().as_ref()).await?;

        // Fetch for assigned requests.
        let requests = ctx
            .network()
            .clone()
            .get_filtered_proof_requests(GetFilteredProofRequestsRequest {
                version: Some(SP1_NETWORK_VERSION.to_string()),
                fulfillment_status: Some(FulfillmentStatus::Assigned.into()),
                minimum_deadline: Some(time_now()),
                fulfiller: Some(owner.clone()),
                limit: Some(1),
                ..Default::default()
            })
            .await?
            .into_inner()
            .requests;

        // If there are no assigned requests, return.
        if requests.is_empty() {
            debug!("found no assigned requests to prove");
            return Ok(());
        }
        info!(
            "🏆 won {} {}",
            if requests.len() == 1 { "the".to_string() } else { requests.len().to_string() },
            if requests.len() == 1 { "auction" } else { "auctions" }
        );

        // There should only be at most one request.
        if requests.len() > 1 {
            error!("expected 1 request, got {}", requests.len());
            return Ok(());
        }

        let request = requests.first().unwrap();

        request.program_name.as_ref().map_or_else(
            || {
                info!(
                    "proving request {}/0x{}",
                    EXPLORER_REQUEST_BASE_URL,
                    hex::encode(&request.request_id)
                );
            },
            |name| {
                info!(
                    "✨ proving program {} for request {}/0x{}",
                    name,
                    EXPLORER_REQUEST_BASE_URL,
                    hex::encode(&request.request_id)
                );
            },
        );

        // Download the program.
        let program_artifact = Artifact {
            id: parse_artifact_id_from_s3_url(&request.program_uri)?,
            label: "program".to_string(),
            expiry: None,
        };

        let elf: Vec<u8> =
            program_artifact.download_program(&self.s3_bucket, &self.s3_region).await?;

        // Download the stdin.
        let stdin_artifact = Artifact {
            id: parse_artifact_id_from_s3_url(&request.stdin_uri)?,
            label: "stdin".to_string(),
            expiry: None,
        };
        let stdin: SP1Stdin =
            stdin_artifact.download_stdin(&self.s3_bucket, &self.s3_region).await?;

        let mode = ProofMode::try_from(request.mode).unwrap_or(ProofMode::Core);
        let mode = match mode {
            ProofMode::Core => SP1ProofMode::Core,
            ProofMode::Compressed => SP1ProofMode::Compressed,
            ProofMode::Plonk => SP1ProofMode::Plonk,
            ProofMode::Groth16 => SP1ProofMode::Groth16,
            ProofMode::UnspecifiedProofMode => unreachable!(),
        };

        // Generate the proving keys and the proof in a separate thread to catch panics.
        let prover = self.prover.clone();
        let result = tokio::task::spawn_blocking(move || {
            panic::catch_unwind(AssertUnwindSafe(move || {
                let (pk, _) = prover.setup(&elf);
                let proof = prover.prove(&pk, &stdin).mode(mode).run();
                proof
            }))
        })
        .await
        .context("proving task failed")?;

        // Set up error capture
        let error_capture = ErrorCapture::new();

        match result {
            Ok(Ok(proof)) => {
                let proof_bytes =
                    bincode::serialize(&proof).context("failed to serialize proof")?;
                let address = ctx.signer().address().to_vec();
                ctx.network()
                    .clone()
                    .with_retry(
                        || async {
                            // Get the nonce.
                            let nonce = ctx
                                .network()
                                .clone()
                                .get_nonce(GetNonceRequest { address: address.clone() })
                                .await?
                                .into_inner()
                                .nonce;

                            // Create and submit the fulfill request.
                            let body = FulfillProofRequestBody {
                                nonce,
                                request_id: request.request_id.clone(),
                                proof: proof_bytes.clone(),
                            };
                            let fulfill_request = FulfillProofRequest {
                                format: MessageFormat::Binary.into(),
                                signature: body.sign(&ctx.signer()).into(),
                                body: Some(body),
                            };
                            ctx.network().clone().fulfill_proof(fulfill_request).await?;
                            Ok(())
                        },
                        "fulfill proof",
                    )
                    .await?;

                Ok(())
            }
            Ok(Err(e)) => {
                let error_msg = error_capture.format_error(e);
                error!("❌ error while proving: {}", error_msg);
                Err(anyhow::anyhow!(error_msg))
            }
            Err(panic_err) => {
                let panic_msg = ErrorCapture::extract_panic_message(panic_err);
                let error_msg = error_capture.format_error(panic_msg);
                error!("❌ proving failed: {}", error_msg);
                Err(anyhow::anyhow!(error_msg))
            }
        }
    }
}

/// Determines if the bidder should bid on a request based on their worst-case throughput.
fn should_bid_on_request(
    worst_case_throughput: f64,
    request_deadline: u64,
    cycle_limit: u64,
    current_time: u64,
) -> bool {
    // Calculate the available time to complete the request.
    let available_time = request_deadline.saturating_sub(current_time);

    // Calculate the required time to complete the request based on worst-case throughput.
    let required_time = (cycle_limit as f64) / worst_case_throughput;

    // Determine if the bidder can meet the deadline.
    required_time <= available_time as f64
}
