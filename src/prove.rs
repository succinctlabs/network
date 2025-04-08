use std::{
    panic::{self, AssertUnwindSafe},
    sync::Arc,
};

use anyhow::{Context, Result};
use futures::future::join_all;
use tokio::spawn;
use tonic::Request;
use tracing::{debug, error, info};

use sp1_prover::components::CpuProverComponents;
use sp1_sdk::{Prover as SP1Prover, SP1ProofMode, SP1Stdin};

use spn_artifacts::{extract_artifact_name, Artifact};
use spn_network_types::{
    FailFulfillmentRequest, FailFulfillmentRequestBody, FulfillProofRequest,
    FulfillProofRequestBody, FulfillmentStatus, GetFilteredProofRequestsRequest, GetNonceRequest,
    MessageFormat, ProofMode, ProofRequest, Signable,
};
use spn_utils::time_now;

use crate::{
    error::ErrorCapture, retry::RetryableRpc, Prover, EXPLORER_URL_REQUEST, REQUEST_LIMIT, VERSION,
};

/// A helper struct to handle panic capturing and proving.
struct ProofTask {
    sp1: Arc<Box<dyn SP1Prover<CpuProverComponents>>>,
    elf: Vec<u8>,
    stdin: SP1Stdin,
    proof_mode: i32,
}

impl ProofTask {
    /// Creates a new proof task with the required components.
    fn new(
        sp1: Arc<Box<dyn SP1Prover<CpuProverComponents>>>,
        elf: Vec<u8>,
        stdin: SP1Stdin,
        proof_mode: i32,
    ) -> Self {
        Self { sp1, elf, stdin, proof_mode }
    }

    /// Executes the proving task and returns the proof bytes.
    fn execute(&self) -> Result<Vec<u8>> {
        // Generate the proving keys and the proof.
        let (pk, _vk) = self.sp1.setup(&self.elf);

        // Determine the proof mode.
        let mode = ProofMode::try_from(self.proof_mode).unwrap_or(ProofMode::UnspecifiedProofMode);
        let proof_mode = match mode {
            ProofMode::Core => SP1ProofMode::Core,
            ProofMode::Compressed => SP1ProofMode::Compressed,
            ProofMode::Plonk => SP1ProofMode::Plonk,
            ProofMode::Groth16 => SP1ProofMode::Groth16,
            _ => SP1ProofMode::Core,
        };

        let proof = self.sp1.prove(&pk, &self.stdin, proof_mode)?;

        // Serialize the proof.
        let proof_bytes = bincode::serialize(&proof).context("failed to serialize proof")?;
        Ok(proof_bytes)
    }
}

/// Queries the network for requests that have been assigned to this prover (status: assigned
/// with this fulfiller address) then spawns a proving task for each.
pub(crate) async fn process_requests(prover: Arc<Prover>, owner: &[u8]) -> Result<()> {
    let req = GetFilteredProofRequestsRequest {
        version: Some(VERSION.to_string()),
        fulfillment_status: Some(FulfillmentStatus::Assigned.into()),
        execution_status: None,
        minimum_deadline: Some(time_now()),
        vk_hash: None,
        requester: None,
        fulfiller: Some(owner.to_vec()),
        limit: Some(REQUEST_LIMIT),
        page: None,
        from: None,
        to: None,
        mode: None,
        not_bid_by: None,
    };

    let network_resp = prover.network.clone().get_filtered_proof_requests(req).await?;
    let requests = network_resp.into_inner().requests;
    if requests.is_empty() {
        debug!("found no assigned requests to prove");
        return Ok(());
    }
    info!(
        "🏆 won {} {}",
        if requests.len() == 1 { "the".to_string() } else { requests.len().to_string() },
        if requests.len() == 1 { "auction" } else { "auctions" }
    );

    let prove_tasks = requests.into_iter().map(|req| {
        let prover = Arc::clone(&prover);
        let request_id = req.request_id.clone();

        spawn(async move {
            if let Err(err) = process_request(&prover, &req).await {
                error!("❌ failed to prove request 0x{}: {:?}", hex::encode(&request_id), err);
                // If proving fails, attempt to mark it as failed.
                if let Err(fail_err) = fail_request(&prover, request_id.clone()).await {
                    error!(
                        "❌ failed to fail the fulfillment of request 0x{}: {:?}",
                        hex::encode(&request_id),
                        fail_err
                    );
                }
            }
        })
    });

    join_all(prove_tasks).await;

    Ok(())
}

/// Proves a single request, then submits it to the network.
async fn process_request(prover: &Prover, req: &ProofRequest) -> Result<()> {
    req.program_name.as_ref().map_or_else(
        || info!("proving request {}/0x{}", EXPLORER_URL_REQUEST, hex::encode(&req.request_id)),
        |name| {
            info!(
                "✨ proving program {} for request {}/0x{}",
                name,
                EXPLORER_URL_REQUEST,
                hex::encode(&req.request_id)
            )
        },
    );

    // Download the program.
    let program_artifact = Artifact {
        id: extract_artifact_name(&req.program_uri)?,
        label: "program".to_string(),
        expiry: None,
    };
    let elf: Vec<u8> =
        program_artifact.download_program(&prover.s3_bucket, &prover.s3_region).await?;

    // Download the stdin.
    let stdin_artifact = Artifact {
        id: extract_artifact_name(&req.stdin_uri)?,
        label: "stdin".to_string(),
        expiry: None,
    };
    let stdin: SP1Stdin =
        stdin_artifact.download_stdin(&prover.s3_bucket, &prover.s3_region).await?;

    // Create the proof task
    let task = ProofTask::new(prover.sp1.clone(), elf, stdin, req.mode);

    // Generate the proving keys and the proof in a separate thread to catch panics.
    let proof_result = tokio::task::spawn_blocking(move || {
        panic::catch_unwind(AssertUnwindSafe(move || task.execute()))
    })
    .await
    .context("proving task failed")?;

    // Set up error capture
    let error_capture = ErrorCapture::new();

    match proof_result {
        Ok(Ok(proof_bytes)) => {
            // Submit the generated proof to the network.
            submit_proof(prover, req.request_id.clone(), proof_bytes).await?;

            // // Calculate the reward.
            // let reward = spn_fee::calculate_request_cost(
            //     req.gas_price.unwrap_or(0),
            //     req.cycles.unwrap_or(0),
            //     req.gas_used.unwrap_or(0),
            //     req.mode,
            // )
            // .map_err(|e| anyhow::anyhow!(e))?;

            // info!("💰 {} earned from proving", spn_fee::format_usdc_as_credits(&reward));

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

/// Submits the generated proof to the network.
async fn submit_proof(prover: &Prover, request_id: Vec<u8>, proof: Vec<u8>) -> Result<()> {
    let address = prover.signer.address().to_vec();
    prover
        .network
        .clone()
        .with_retry(
            || async {
                // Get the nonce.
                let req = Request::new(GetNonceRequest { address: address.clone() });
                let nonce = prover.network.clone().get_nonce(req).await?.into_inner().nonce;

                // Create and submit the fulfill request.
                let body = FulfillProofRequestBody {
                    nonce,
                    request_id: request_id.clone(),
                    proof: proof.clone(),
                };
                let fulfill_request = FulfillProofRequest {
                    format: MessageFormat::Binary.into(),
                    signature: body.sign(&prover.signer).into(),
                    body: Some(body),
                };
                prover.network.clone().fulfill_proof(fulfill_request).await?;
                Ok(())
            },
            "fulfill proof",
        )
        .await?;

    info!("✅ fulfilled request {}/0x{}", EXPLORER_URL_REQUEST, hex::encode(&request_id));
    Ok(())
}

/// Fails a request by sending a failure message to the network.
async fn fail_request(prover: &Prover, request_id: Vec<u8>) -> Result<()> {
    let address = prover.signer.address().to_vec();
    prover
        .network
        .clone()
        .with_retry(
            || async {
                // Get the nonce.
                let req = Request::new(GetNonceRequest { address: address.clone() });
                let nonce = prover.network.clone().get_nonce(req).await?.into_inner().nonce;

                // Create and submit the fail request.
                let body = FailFulfillmentRequestBody { nonce, request_id: request_id.clone() };
                let fail_request = FailFulfillmentRequest {
                    format: MessageFormat::Binary.into(),
                    signature: body.sign(&prover.signer).into(),
                    body: Some(body),
                };
                prover.network.clone().fail_fulfillment(fail_request).await?;
                Ok(())
            },
            "fail fulfillment",
        )
        .await?;

    info!("❌ failed request {}/0x{}", EXPLORER_URL_REQUEST, hex::encode(&request_id));
    Ok(())
}
