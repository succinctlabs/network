use std::{
    panic::{self, AssertUnwindSafe},
    sync::Arc,
    time::{Duration, Instant, SystemTime},
};

use alloy_primitives::U256;
use alloy_signer_local::PrivateKeySigner;
use anyhow::Context;
use chrono::{self, DateTime};
use nvml_wrapper::Nvml;
use sp1_sdk::{EnvProver, ProverClient, SP1ProofMode, SP1Stdin};
use spn_artifacts::{parse_artifact_id_from_s3_url, Artifact};
use spn_network_types::{
    prover_network_client::ProverNetworkClient, BidRequest, BidRequestBody, FulfillProofRequest,
    FulfillProofRequestBody, FulfillmentStatus, GetFilteredProofRequestsRequest, GetNonceRequest,
    GetProofRequestDetailsRequest, MessageFormat, ProofMode, Signable,
};
use spn_rpc::{fetch_owner, RetryableRpc};
use spn_utils::{time_now, ErrorCapture};
use sysinfo::{CpuExt, System, SystemExt};
use tokio::sync::Mutex;
use tonic::{async_trait, transport::Channel};
use tracing::{error, info};

use crate::{NodeBidder, NodeContext, NodeMetrics, NodeMonitor, NodeProver, SP1_NETWORK_VERSION};

/// A context that implements [`NodeContext`] for a serial node.
///
/// This context is compatible with both [`SerialBidder`] and [`SerialProver`].
#[derive(Debug)]
pub struct SerialContext {
    /// The network client for the node.
    pub network: ProverNetworkClient<Channel>,
    /// The signer for the node.
    pub signer: PrivateKeySigner,
    /// The metrics for the node.
    pub metrics: NodeMetrics,
}

impl SerialContext {
    /// Create a new [`SerialContext`].
    pub fn new(network: ProverNetworkClient<Channel>, signer: PrivateKeySigner) -> Self {
        Self {
            network,
            signer,
            metrics: NodeMetrics {
                fulfilled: Mutex::new(0),
                online_since: SystemTime::now(),
                total_cycles: Mutex::new(0),
                total_proving_time: Mutex::new(Duration::from_secs(0)),
            },
        }
    }
}

impl NodeContext for SerialContext {
    fn network(&self) -> &ProverNetworkClient<Channel> {
        &self.network
    }

    fn signer(&self) -> &PrivateKeySigner {
        &self.signer
    }

    fn metrics(&self) -> &NodeMetrics {
        &self.metrics
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

#[async_trait]
impl<C: NodeContext> NodeBidder<C> for SerialBidder {
    #[allow(clippy::too_many_lines)]
    async fn bid(&self, ctx: &C) -> anyhow::Result<()> {
        const SERIAL_BIDDER_TAG: &str = "\x1b[34m[SerialBidder]\x1b[0m";

        // Fetch the owner.
        let owner = fetch_owner(ctx.network(), ctx.signer().address().as_ref()).await?;
        info!(owner = %hex::encode(&owner), "{SERIAL_BIDDER_TAG} Fetched owner.");

        // Fetch for assigned requests.
        let assigned_requests = ctx
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
        info!(count = %assigned_requests.len(), "{SERIAL_BIDDER_TAG} Fetched assigned proof requests.");

        if !assigned_requests.is_empty() {
            info!(
                "{SERIAL_BIDDER_TAG} At least one assigned proof request found. Skipping the bidding process for now."
            );
            return Ok(());
        }

        // Fetch for unassigned requests.
        let unassigned_requests = ctx
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
        info!(count = %unassigned_requests.len(), "{SERIAL_BIDDER_TAG} Fetched unassigned proof requests.");

        // If there are no open requests, return.
        if unassigned_requests.is_empty() {
            info!("{SERIAL_BIDDER_TAG} Found no unassigned requests to bid on.");
            return Ok(());
        }

        // There should only be at most one request.
        if unassigned_requests.len() > 1 {
            info!(
                "{SERIAL_BIDDER_TAG} Found more than one unassigned request to bid on. Skipping..."
            );
            return Ok(());
        }

        let request = unassigned_requests.first().unwrap();
        let request_id = hex::encode(&request.request_id);
        let address = ctx.signer().address().to_vec();

        info!("{SERIAL_BIDDER_TAG} Found one unassigned request to bid on.");
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
                    info!(nonce = %nonce, "{SERIAL_BIDDER_TAG} Fetched account nonce.");

                    // Get request details to access the deadline.
                    let request = ctx
                        .network()
                        .clone()
                        .get_proof_request_details(GetProofRequestDetailsRequest {
                            request_id: hex::decode(request_id.clone())?,
                        })
                        .await?
                        .into_inner()
                        .request
                        .ok_or_else(|| anyhow::anyhow!("request details not found"))?;

                    // Log the request details in a structured format.
                    let current_time = time_now();
                    let remaining_time = request.deadline.saturating_sub(current_time);
                    let required_time = ((request.gas_limit as f64) / self.throughput) as u64;

                    info!(
                        request_id = %request_id,
                        vk_hash = %hex::encode(request.vk_hash),
                        version = %request.version,
                        mode = %request.mode,
                        strategy = %request.strategy,
                        requester = %hex::encode(request.requester),
                        tx_hash = %hex::encode(request.tx_hash),
                        program_uri = %request.program_uri,
                        stdin_uri = %request.stdin_uri,
                        gas_limit = %request.gas_limit,
                        cycle_limit = %request.cycle_limit,
                        created_at = %request.created_at,
                        created_at_utc = %DateTime::from_timestamp(i64::try_from(request.created_at).unwrap_or_default(), 0).unwrap_or_default(),
                        deadline = %request.deadline,
                        deadline_utc = %DateTime::from_timestamp(i64::try_from(request.deadline).unwrap_or_default(), 0).unwrap_or_default(),
                        remaining_time = %remaining_time,
                        remaining_time_minutes = %remaining_time / 60,
                        remaining_time_seconds = %remaining_time % 60,
                        required_time = %required_time,
                        required_time_minutes = %required_time / 60,
                        required_time_seconds = %required_time % 60,
                        "{SERIAL_BIDDER_TAG} Fetched request details."
                    );

                    if remaining_time < required_time {
                        info!(request_id = %request_id, remaining_time = %remaining_time, required_time = %required_time, "{SERIAL_BIDDER_TAG} Not enough time to bid on request. Skipping...");
                        return Ok(());
                    }

                    // Bid on the request.
                    info!(request_id = %request_id, bid_amount = %self.bid, "{SERIAL_BIDDER_TAG} Submitting a bid for request");
                    let body = BidRequestBody {
                        nonce,
                        request_id: hex::decode(request_id.clone())
                            .context("failed to decode request_id")?,
                        amount: self.bid.to_string(),
                    };
                    let bid_request = BidRequest {
                        format: MessageFormat::Binary.into(),
                        signature: body.sign(&ctx.signer()).into(),
                        body: Some(body),
                    };
                    ctx.network().clone().bid(bid_request).await?;

                    Ok(())
                },
                "Bid",
            )
            .await?;

        Ok(())
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
impl<C: NodeContext> NodeProver<C> for SerialProver {
    #[allow(clippy::too_many_lines)]
    async fn prove(&self, ctx: &C) -> anyhow::Result<()> {
        const SERIAL_PROVER_TAG: &str = "\x1b[33m[SerialProver]\x1b[0m";

        // Fetch the owner.
        let owner = fetch_owner(ctx.network(), ctx.signer().address().as_ref()).await?;
        info!(owner = %hex::encode(&owner), "{SERIAL_PROVER_TAG} Fetched owner.");

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
        info!(count = %requests.len(), "{SERIAL_PROVER_TAG} Fetched assigned proof requests.");

        // If there are no assigned requests, return.
        if requests.is_empty() {
            info!("{SERIAL_PROVER_TAG} Found no assigned requests to prove.");
            return Ok(());
        }

        for request in requests {
            // Log the request details.
            info!(
                request_id = %hex::encode(&request.request_id),
                vk_hash = %hex::encode(request.vk_hash),
                version = %request.version,
                mode = %request.mode,
                strategy = %request.strategy,
                requester = %hex::encode(request.requester),
                tx_hash = %hex::encode(request.tx_hash),
                program_uri = %request.program_uri,
                stdin_uri = %request.stdin_uri,
                cycle_limit = %request.cycle_limit,
                created_at = %request.created_at,
                created_at_utc = %DateTime::from_timestamp(i64::try_from(request.created_at).unwrap_or_default(), 0).unwrap_or_default(),
                deadline = %request.deadline,
                deadline_utc = %DateTime::from_timestamp(i64::try_from(request.deadline).unwrap_or_default(), 0).unwrap_or_default(),
                "{SERIAL_PROVER_TAG} Proving request..."
            );

            // Download the program.
            let program_artifact_id = parse_artifact_id_from_s3_url(&request.program_uri)?;
            let program_artifact = Artifact {
                id: program_artifact_id.clone(),
                label: "program".to_string(),
                expiry: None,
            };
            let program: Vec<u8> =
                program_artifact.download_program(&self.s3_bucket, &self.s3_region).await?;
            info!(program_size = %program.len(), artifact_id = %hex::encode(program_artifact_id), "{SERIAL_PROVER_TAG} Downloaded program.");

            // Download the stdin.
            let stdin_artifact_id = parse_artifact_id_from_s3_url(&request.stdin_uri)?;
            let stdin_artifact = Artifact {
                id: stdin_artifact_id.clone(),
                label: "stdin".to_string(),
                expiry: None,
            };
            let stdin: SP1Stdin =
                stdin_artifact.download_stdin(&self.s3_bucket, &self.s3_region).await?;
            info!(stdin_size = %stdin.buffer.iter().map(std::vec::Vec::len).sum::<usize>(), artifact_id = %hex::encode(stdin_artifact_id), "{SERIAL_PROVER_TAG} Downloaded stdin.");

            // Generate the proving keys and the proof in a separate thread to catch panics.
            let prover = self.prover.clone();
            let mode = ProofMode::try_from(request.mode).unwrap_or(ProofMode::Core);
            let mode = match mode {
                ProofMode::Core => SP1ProofMode::Core,
                ProofMode::Compressed => SP1ProofMode::Compressed,
                ProofMode::Plonk => SP1ProofMode::Plonk,
                ProofMode::Groth16 => SP1ProofMode::Groth16,
                ProofMode::UnspecifiedProofMode => unreachable!(),
            };
            let result = tokio::task::spawn_blocking(move || {
                panic::catch_unwind(AssertUnwindSafe(move || {
                    let start = Instant::now();
                    info!("{SERIAL_PROVER_TAG} Setting up proving key...");
                    let (pk, _) = prover.setup(&program);
                    info!(duration = %start.elapsed().as_secs_f64(), "{SERIAL_PROVER_TAG} Set up proving key.");

                    let start = Instant::now();
                    info!("{SERIAL_PROVER_TAG} Executing program...");
                    let (_, report) = prover.execute(&pk.elf, &stdin).run().unwrap();
                    let cycles = report.total_instruction_count();
                    info!(duration = %start.elapsed().as_secs_f64(), cycles = %cycles, "{SERIAL_PROVER_TAG} Executed program.");

                    let start = Instant::now();
                    info!("{SERIAL_PROVER_TAG} Generating proof...");
                    let proof = prover.prove(&pk, &stdin).mode(mode).run();
                    let proving_time = start.elapsed();
                    info!(duration = %proving_time.as_secs_f64(), cycles = %cycles, "{SERIAL_PROVER_TAG} Proof generation complete.");
                    (proof, cycles, proving_time)
                }))
            })
            .await
            .context("proving task failed")?;

            // Set up error capture
            let error_capture = ErrorCapture::new();

            match result {
                Ok((Ok(proof), cycles, proving_time)) => {
                    // Update the metrics.
                    let metrics = ctx.metrics();
                    *metrics.total_cycles.lock().await += cycles;
                    *metrics.total_proving_time.lock().await += proving_time;
                    *metrics.fulfilled.lock().await += 1;

                    // Serialize the proof.
                    let proof_bytes =
                        bincode::serialize(&proof).context("failed to serialize proof")?;

                    // Fulfill the proof.
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
                                info!(nonce = %nonce, "{SERIAL_PROVER_TAG} Fetched account nonce.");

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
                                info!(request_id = %hex::encode(&request.request_id), proof_size = %proof_bytes.len(), "{SERIAL_PROVER_TAG} Proof fulfillment submitted.");
                                Ok(())
                            },
                            "Fulfill",
                        )
                        .await?;
                }
                Ok((Err(e), _, _)) => {
                    let error_msg = error_capture.format_error(e);
                    error!("{SERIAL_PROVER_TAG} {error_msg}");
                }
                Err(panic_err) => {
                    let panic_msg = ErrorCapture::extract_panic_message(panic_err);
                    let error_msg = error_capture.format_error(panic_msg);
                    error!("{SERIAL_PROVER_TAG} {error_msg}");
                }
            }
        }

        Ok(())
    }
}

/// The metrics for a serial node.
#[derive(Debug, Clone)]
pub struct SerialMonitor;

#[async_trait]
impl NodeMonitor<SerialContext> for SerialMonitor {
    async fn record(&self, ctx: &SerialContext) -> anyhow::Result<()> {
        const SERIAL_MONITOR_TAG: &str = "\x1b[35m[SerialMonitor]\x1b[0m";

        // Log the node metrics.
        let metrics = ctx.metrics();
        let fulfilled = *metrics.fulfilled.lock().await;
        let total_cycles = *metrics.total_cycles.lock().await;
        let total_proving_time = *metrics.total_proving_time.lock().await;
        let throughput = total_cycles as f64 / total_proving_time.as_secs() as f64;
        let throughput = if throughput.is_nan() {
            "0 MHz".to_string()
        } else {
            format!("{:.2} MHz", throughput / 1_000_000.0)
        };
        let total_cycles = format!("{:.2}M", total_cycles as f64 / 1_000_000.0);
        let total_proving_time = humantime::format_duration(total_proving_time).to_string();
        info!(
            fulfilled = %fulfilled,
            total_cycles = %total_cycles,
            total_proving_time = %total_proving_time,
            throughput = %throughput,
            "{SERIAL_MONITOR_TAG} Checking node metrics..."
        );

        // Get system metrics.
        let mut system = System::new_all();
        system.refresh_all();

        // Get CPU usage.
        let cpu_usage = system.global_cpu_info().cpu_usage();

        // Get RAM usage
        let total_memory = system.total_memory();
        let used_memory = system.used_memory();

        // Get disk usage.
        let total_disk_space =
            system.disks().iter().map(sysinfo::DiskExt::total_space).sum::<u64>();
        let used_disk_space =
            system.disks().iter().map(sysinfo::DiskExt::available_space).sum::<u64>();

        // Get device metrics.
        let nvml = Nvml::init()?;
        let device = nvml.device_by_index(0)?;
        let utilization = device.utilization_rates()?;
        let memory = device.memory_info()?;

        // Log the system health metrics including GPU and VRAM usage.
        info!(
            cpu_usage = %cpu_usage,
            gpu_usage = %utilization.gpu,
            vram_used = %memory.used,
            vram_total = %memory.total,
            ram_used = %used_memory,
            ram_total = %total_memory,
            disk_used_percent = %(used_disk_space as f64 / total_disk_space as f64) * 100.0,
            "{SERIAL_MONITOR_TAG} Checking node health..."
        );

        Ok(())
    }
}
