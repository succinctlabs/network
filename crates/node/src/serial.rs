use std::{
    collections::HashSet,
    env,
    panic::{self, AssertUnwindSafe},
    sync::{atomic, Arc},
    time::{Duration, Instant, SystemTime},
};

use alloy_primitives::U256;
use alloy_signer_local::PrivateKeySigner;
use anyhow::{Context, Result};
use chrono::{self, DateTime};
use nvml_wrapper::Nvml;
use sp1_sdk::{EnvProver, SP1ProofMode, SP1Stdin};
use spn_artifacts::{parse_artifact_id_from_url, Artifact};
use spn_network_types::{
    prover_network_client::ProverNetworkClient, BidRequest, BidRequestBody, ExecutionStatus,
    FailFulfillmentRequest, FailFulfillmentRequestBody, FulfillProofRequest,
    FulfillProofRequestBody, FulfillmentStatus, GetFilteredProofRequestsRequest, GetNonceRequest,
    GetProofRequestDetailsRequest, MessageFormat, ProofMode, Signable, ProofRequest,
};
use spn_rpc::{fetch_owner, RetryableRpc};
use spn_utils::time_now;
use sysinfo::{CpuExt, System, SystemExt};
use tokio::sync::Mutex;
use tokio::time;
use tonic::{async_trait, transport::Channel};
use tracing::{error, info, warn};

use crate::{NodeBidder, NodeContext, NodeMetrics, NodeMonitor, NodeProver, SP1_NETWORK_VERSION};

const REQUEST_LIMIT: u32 = 1;
const OWNER_FETCH_RETRY_SECONDS: u64 = 5;
const STREAM_ERROR_RECONNECT_SECONDS: u64 = 15;
const STREAM_CLEAN_END_RECONNECT_SECONDS: u64 = 5;

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
    async fn run_bidding_service(&self, ctx: Arc<C>) -> Result<()> {
        const SERIAL_BIDDER_TAG: &str = "\x1b[34m[SerialBidder][0m";
        info!("{SERIAL_BIDDER_TAG} Starting bidding service...");

        let owner = fetch_owner(ctx.network(), ctx.signer().address().as_ref())
            .await
            .context("Failed to fetch owner for bidding service. Terminating service.")?;
        info!(owner = %hex::encode(&owner), "{SERIAL_BIDDER_TAG} Fetched owner.");

        loop {
            // Check if we are already assigned a request. If so, don't bid on new ones.
            let assigned_check_req = GetFilteredProofRequestsRequest {
                version: Some(SP1_NETWORK_VERSION.to_string()),
                fulfillment_status: Some(FulfillmentStatus::Assigned.into()),
                fulfiller: Some(owner.clone()),
                limit: Some(REQUEST_LIMIT),
                ..Default::default()
            };
            match ctx.network().clone().get_filtered_proof_requests(assigned_check_req).await {
                Ok(assigned_response) => {
                    if !assigned_response.into_inner().requests.is_empty() {
                        // info!("{SERIAL_BIDDER_TAG} Node is busy with an assigned request. Pausing bidding.");
                        time::sleep(Duration::from_secs(STREAM_ERROR_RECONNECT_SECONDS)).await; // Use a general delay
                        continue;
                    }
                }
                Err(e) => {
                    warn!("{SERIAL_BIDDER_TAG} Failed to check for assigned requests: {:?}. Retrying...", e);
                    time::sleep(Duration::from_secs(STREAM_ERROR_RECONNECT_SECONDS)).await;
                    continue;
                }
            }

            info!("{SERIAL_BIDDER_TAG} Node is not busy. Subscribing to unassigned proof requests...");
            let unassigned_stream_req = GetFilteredProofRequestsRequest {
                version: Some(SP1_NETWORK_VERSION.to_string()),
                fulfillment_status: Some(FulfillmentStatus::Requested.into()),
                minimum_deadline: Some(time_now()),
                not_bid_by: Some(owner.clone()),
                limit: Some(REQUEST_LIMIT),
                ..Default::default()
            };

            let mut stream = match ctx.network().clone().subscribe_proof_requests(unassigned_stream_req).await {
                Ok(response) => response.into_inner(),
                Err(e) => {
                    warn!("{SERIAL_BIDDER_TAG} Failed to subscribe to unassigned requests stream: {:?}. Retrying in {}s", e, STREAM_ERROR_RECONNECT_SECONDS);
                    time::sleep(Duration::from_secs(STREAM_ERROR_RECONNECT_SECONDS)).await;
                    continue;
                }
            };
            info!("{SERIAL_BIDDER_TAG} Subscribed to unassigned proof requests stream.");

            loop { // Inner loop to process messages from the current stream
                match stream.message().await {
                    Ok(Some(request)) => {
                        let request_id_hex = hex::encode(&request.request_id);
                        info!("{SERIAL_BIDDER_TAG} Received unassigned request: {}", request_id_hex);

                        // Process this one request
                        let address = ctx.signer().address().to_vec();
                        let bid_result = ctx.network()
                            .clone()
                            .with_retry(
                                || async {
                                    let nonce = ctx
                                        .network()
                                        .clone()
                                        .get_nonce(GetNonceRequest { address: address.clone() })
                                        .await?
                                        .into_inner()
                                        .nonce;
                                    // info!(nonce = %nonce, "{SERIAL_BIDDER_TAG} Fetched account nonce for request {}", request_id_hex);

                                    let request_details = ctx
                                        .network()
                                        .clone()
                                        .get_proof_request_details(GetProofRequestDetailsRequest {
                                            request_id: request.request_id.clone(),
                                        })
                                        .await?
                                        .into_inner()
                                        .request
                                        .ok_or_else(|| anyhow::anyhow!("Request details not found for {}", request_id_hex))?;

                                    let current_time = time_now();
                                    let remaining_time = request_details.deadline.saturating_sub(current_time);
                                    let required_time = ((request_details.gas_limit as f64) / self.throughput) as u64;

                                    info!(
                                        request_id = %request_id_hex,
                                        // vk_hash = %hex::encode(request_details.vk_hash),
                                        // version = %request_details.version,
                                        // mode = %request_details.mode,
                                        // strategy = %request_details.strategy,
                                        // requester = %hex::encode(request_details.requester),
                                        // tx_hash = %hex::encode(request_details.tx_hash),
                                        // program_uri = %request_details.program_public_uri,
                                        // stdin_uri = %request_details.stdin_public_uri,
                                        gas_limit = %request_details.gas_limit,
                                        // cycle_limit = %request_details.cycle_limit,
                                        // created_at = %request_details.created_at,
                                        // created_at_utc = %DateTime::from_timestamp(i64::try_from(request_details.created_at).unwrap_or_default(), 0).unwrap_or_default(),
                                        deadline = %request_details.deadline,
                                        // deadline_utc = %DateTime::from_timestamp(i64::try_from(request_details.deadline).unwrap_or_default(), 0).unwrap_or_default(),
                                        remaining_time_sec = %remaining_time,
                                        required_time_sec = %required_time,
                                        "{} Fetched request details for {}.", SERIAL_BIDDER_TAG, request_id_hex
                                    );

                                    if remaining_time < required_time {
                                        info!("{SERIAL_BIDDER_TAG} Not enough time (remaining: {}s, required: {}s) to bid on request {}. Skipping...", remaining_time, required_time, request_id_hex);
                                        return Ok(()); // Ok to skip, not an error for the retry
                                    }

                                    info!("{SERIAL_BIDDER_TAG} Submitting bid (amount: {}) for request {}", self.bid, request_id_hex);
                                    let body = BidRequestBody {
                                        nonce,
                                        request_id: request.request_id.clone(),
                                        amount: self.bid.to_string(),
                                    };
                                    let bid_request = BidRequest {
                                        format: MessageFormat::Binary.into(),
                                        signature: body.sign(&ctx.signer()).into(),
                                        body: Some(body),
                                    };
                                    ctx.network().clone().bid(bid_request).await?;
                                    info!("{SERIAL_BIDDER_TAG} Successfully bid on request {}", request_id_hex);
                                    Ok(())
                                },
                                "Bid",
                            )
                            .await;

                        if let Err(e) = bid_result {
                            error!("{SERIAL_BIDDER_TAG} Failed to bid on request {}: {:?}", request_id_hex, e);
                            // Decide if we should break from inner loop and re-establish stream or continue
                        }
                        // Since it's a serial bidder, after attempting to bid (success or fail),
                        // break from inner loop to re-check if node is busy and then re-subscribe.
                        // This ensures we only try to bid on one thing at a time from the stream.
                        break;
                    }
                    Ok(None) => {
                        warn!("{SERIAL_BIDDER_TAG} Unassigned requests stream ended cleanly. Reconnecting in {}s...", STREAM_CLEAN_END_RECONNECT_SECONDS);
                        time::sleep(Duration::from_secs(STREAM_CLEAN_END_RECONNECT_SECONDS)).await;
                        break; // Break inner loop to re-establish stream in outer loop
                    }
                    Err(e) => {
                        error!("{SERIAL_BIDDER_TAG} Error receiving from unassigned requests stream: {:?}. Reconnecting in {}s...", e, STREAM_ERROR_RECONNECT_SECONDS);
                        time::sleep(Duration::from_secs(STREAM_ERROR_RECONNECT_SECONDS)).await;
                        break; // Break inner loop to re-establish stream in outer loop
                    }
                }
            } // End of inner stream processing loop
        } // End of outer service loop
    }
}

/// A serial prover.
///
/// This prover will generate proofs for requests sequentially using an [`EnvProver`].
pub struct SerialProver {
    /// The underlying prover for the node that will be used to generate proofs.
    prover: Arc<EnvProver>,
    /// Registry of unexecutable request IDs that should be cancelled.
    unexecutable_requests: Arc<Mutex<HashSet<Vec<u8>>>>,
}

impl Default for SerialProver {
    fn default() -> Self {
        Self::new()
    }
}

impl SerialProver {
    /// Create a new [`SerialProver`].
    #[must_use]
    pub fn new() -> Self {
        // Set the SP1_PROVER environment variable based on CUDA support.
        if spn_utils::has_cuda_support() {
            info!("CUDA support detected, using GPU prover");
            env::set_var("SP1_PROVER", "cuda");
        } else {
            info!("no CUDA support detected, using CPU prover");
            env::set_var("SP1_PROVER", "cpu");
        };

        Self {
            prover: Arc::new(EnvProver::new()),
            unexecutable_requests: Arc::new(Mutex::new(HashSet::new())),
        }
    }

    /// Checks the network for unexecutable requests and maintains a registry.
    fn ensure_unexecutable_check_task_running(&self, ctx: &SerialContext, owner: Vec<u8>) {
        // Use a static AtomicBool to ensure we only start the task once across the entire
        // application.
        static TASK_STARTED: atomic::AtomicBool = atomic::AtomicBool::new(false);

        // If the task is already running, don't start another one.
        if TASK_STARTED
            .compare_exchange(false, true, atomic::Ordering::SeqCst, atomic::Ordering::SeqCst)
            .is_err()
        {
            return;
        }

        // Clone the references to use in the background task.
        let unexecutable_requests_clone = self.unexecutable_requests.clone();
        let network_client_for_task = ctx.network().clone();
        // let signer_address_for_task = ctx.signer().address().to_vec(); // Owner is now passed in

        // Spawn a background task to check for unexecutable requests.
        tokio::spawn(async move {
            const SERIAL_PROVER_TAG: &str = "[33m[SerialProver][0m";

            loop {
                // Owner is passed directly, no need to fetch it inside the loop.
                // let owner = match fetch_owner(&network_client_for_task, &signer_address_for_task).await {
                //     Ok(owner) => owner,
                //     Err(e) => {
                //         tracing::warn!("{SERIAL_PROVER_TAG} Failed to fetch owner for unexecutable stream: {:?}. Retrying in {}s.", e, OWNER_FETCH_RETRY_SECONDS);
                //         time::sleep(Duration::from_secs(OWNER_FETCH_RETRY_SECONDS)).await;
                //         continue;
                //     }
                // };

                // Define the stream request
                let stream_req_payload = GetFilteredProofRequestsRequest {
                    version: Some(SP1_NETWORK_VERSION.to_string()),
                    fulfillment_status: Some(FulfillmentStatus::Assigned.into()),
                    execution_status: Some(ExecutionStatus::Unexecutable.into()),
                    fulfiller: Some(owner.clone()), // Use the passed-in owner
                    minimum_deadline: None,
                    not_bid_by: None,
                    requester: None,
                    limit: None, // Stream all unexecutable for this owner
                    ..Default::default()
                };

                // Attempt to establish the stream
                let mut stream = match network_client_for_task.clone().subscribe_proof_requests(stream_req_payload).await {
                    Ok(response) => response.into_inner(),
                    Err(e) => {
                        tracing::warn!("{SERIAL_PROVER_TAG} Failed to establish stream for unexecutable requests: {:?}. Retrying in {}s.", e, STREAM_ERROR_RECONNECT_SECONDS);
                        time::sleep(Duration::from_secs(STREAM_ERROR_RECONNECT_SECONDS)).await;
                        continue; // Retry the outer loop to re-establish stream
                    }
                };
                tracing::info!("{SERIAL_PROVER_TAG} Established stream for unexecutable requests assigned to owner {}.", hex::encode(&owner));

                // Inner loop for processing messages from the current stream connection
                loop {
                    match stream.message().await {
                        Ok(Some(request)) => {
                            let request_id_hex = hex::encode(&request.request_id);
                            let mut registry = unexecutable_requests_clone.lock().await;
                            if registry.insert(request.request_id.clone()) {
                                tracing::info!(
                                    request_id = %request_id_hex,
                                    "{SERIAL_PROVER_TAG} Added request to unexecutable registry via stream"
                                );
                            }
                        }
                        Ok(None) => {
                            tracing::warn!("{SERIAL_PROVER_TAG} Unexecutable requests stream ended. Reconnecting in {}s.", STREAM_CLEAN_END_RECONNECT_SECONDS);
                            time::sleep(Duration::from_secs(STREAM_CLEAN_END_RECONNECT_SECONDS)).await;
                            break; // Break inner loop to reconnect by re-entering outer loop
                        }
                        Err(status) => {
                            tracing::warn!("{SERIAL_PROVER_TAG} Error receiving from unexecutable requests stream: {:?}. Reconnecting in {}s.", status, STREAM_ERROR_RECONNECT_SECONDS);
                            time::sleep(Duration::from_secs(STREAM_ERROR_RECONNECT_SECONDS)).await;
                            break; // Break inner loop to reconnect by re-entering outer loop
                        }
                    }
                }
            }
        });
    }
}

/// Attempts to notify the network that proving a request failed.
async fn fail_request<C: NodeContext>(ctx: &C, request_id: Vec<u8>) -> Result<()> {
    const SERIAL_PROVER_TAG: &str = "\x1b[33m[SerialProver]\x1b[0m";
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

                // Create and submit the fail request.
                let body = FailFulfillmentRequestBody { nonce, request_id: request_id.clone() };
                let fail_request = FailFulfillmentRequest {
                    format: MessageFormat::Binary.into(),
                    signature: body.sign(&ctx.signer()).into(),
                    body: Some(body),
                };
                ctx.network().clone().fail_fulfillment(fail_request).await?;
                info!(request_id = %hex::encode(&request_id), "{SERIAL_PROVER_TAG} Notified network of failed fulfillment.");
                Ok(())
            },
            "FailFulfillment",
        )
        .await?;
    Ok(())
}

/// The metrics for a serial node.
#[derive(Debug, Clone)]
pub struct SerialMonitor {
    pub has_cuda_support: bool,
}

/// Holds GPU metrics obtained from NVML.
#[derive(Debug, Clone, Copy)]
struct GpuMetrics {
    gpu_usage: u32,
    vram_used: u64,
    vram_total: u64,
}

impl Default for SerialMonitor {
    fn default() -> Self {
        Self::new()
    }
}

impl SerialMonitor {
    #[must_use]
    pub fn new() -> Self {
        Self { has_cuda_support: spn_utils::has_cuda_support() }
    }

    /// Attempts to fetch GPU metrics using NVML.
    fn try_get_gpu_metrics() -> Option<GpuMetrics> {
        Nvml::init().ok().and_then(|nvml| {
            nvml.device_by_index(0).ok().and_then(|device| {
                device.utilization_rates().ok().and_then(|utilization| {
                    device.memory_info().ok().map(|memory| GpuMetrics {
                        gpu_usage: utilization.gpu,
                        vram_used: memory.used,
                        vram_total: memory.total,
                    })
                })
            })
        })
    }
}

#[async_trait]
impl NodeMonitor<SerialContext> for SerialMonitor {
    async fn record(&self, ctx: &SerialContext) -> Result<()> {
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

        // Log basic system health metrics.
        info!(
            cpu_usage = %cpu_usage,
            ram_used = %used_memory,
            ram_total = %total_memory,
            disk_used_percent = %(used_disk_space as f64 / total_disk_space as f64) * 100.0,
            "{SERIAL_MONITOR_TAG} Checking basic node health..."
        );

        // Conditionally check and log GPU metrics.
        if self.has_cuda_support {
            if let Some(gpu_metrics) = Self::try_get_gpu_metrics() {
                info!(
                    gpu_usage = %gpu_metrics.gpu_usage,
                    vram_used = %gpu_metrics.vram_used,
                    vram_total = %gpu_metrics.vram_total,
                    "{SERIAL_MONITOR_TAG} Checking GPU health..."
                );
            }
        }

        Ok(())
    }
}

#[async_trait]
impl<C: NodeContext> NodeProver<C> for SerialProver {
    #[allow(clippy::too_many_lines)]
    async fn run_proving_service(&self, ctx: Arc<C>) -> Result<()> {
        const SERIAL_PROVER_TAG: &str = "[33m[SerialProver][0m";
        info!("{SERIAL_PROVER_TAG} Starting proving service...");

        let owner = fetch_owner(ctx.network(), ctx.signer().address().as_ref())
            .await
            .context("Failed to fetch owner for proving service. Terminating service.")?;
        info!(owner = %hex::encode(&owner), "{SERIAL_PROVER_TAG} Fetched owner for proving service.");

        // Ensure the background unexecutable check task is running, now passing the owner.
        self.ensure_unexecutable_check_task_running(ctx.as_ref(), owner.clone());

        loop { // Outer loop for stream reconnection
            info!("{SERIAL_PROVER_TAG} Subscribing to assigned proof requests...");
            let assigned_stream_req = GetFilteredProofRequestsRequest {
                version: Some(SP1_NETWORK_VERSION.to_string()),
                fulfillment_status: Some(FulfillmentStatus::Assigned.into()),
                minimum_deadline: Some(time_now()), // Consider if needed for assigned stream
                fulfiller: Some(owner.clone()),
                // limit: Some(REQUEST_LIMIT), // Stream will give one by one
                ..Default::default()
            };

            let mut stream = match ctx.network().clone().subscribe_proof_requests(assigned_stream_req).await {
                Ok(response) => response.into_inner(),
                Err(e) => {
                    warn!("{SERIAL_PROVER_TAG} Failed to subscribe to assigned requests stream: {:?}. Retrying in {}s", e, STREAM_ERROR_RECONNECT_SECONDS);
                    time::sleep(Duration::from_secs(STREAM_ERROR_RECONNECT_SECONDS)).await;
                    continue; // Retry subscribing
                }
            };
            info!("{SERIAL_PROVER_TAG} Subscribed to assigned proof requests stream.");

            // Inner loop to process messages from the current stream
            'request_processing_loop: loop {
                match stream.message().await {
                    Ok(Some(request)) => {
                        let request_id_for_processing = request.request_id.clone();
                        let request_id_hex = hex::encode(&request_id_for_processing);
                        info!("{SERIAL_PROVER_TAG} Received assigned request to prove: {}", request_id_hex);

                        // Process this one request
                        // Check if this request is already known to be unexecutable.
                        let unexecutable_registry = self.unexecutable_requests.lock().await;
                        if unexecutable_registry.contains(&request_id_for_processing) {
                            info!(
                                request_id = %request_id_hex,
                                "{SERIAL_PROVER_TAG} Skipping request marked as UNEXECUTABLE (found before proving attempt)"
                            );
                            drop(unexecutable_registry); // Release lock
                            report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "skipped UNEXECUTABLE")
                                .await;
                            continue; // Get next message from stream
                        }
                        drop(unexecutable_registry); // Release lock

                        info!(
                            request_id = %request_id_hex,
                            // ... (full logging of request details as before)
                            "{SERIAL_PROVER_TAG} Proving request..."
                        );

                        // Download the program.
                        let program_artifact_id = match parse_artifact_id_from_url(&request.program_public_uri) {
                            Ok(id) => id,
                            Err(e) => {
                                error!("{SERIAL_PROVER_TAG} Failed to parse program URI for request {}: {:?}. Marking as failed.", request_id_hex, e);
                                report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "program URI parse failure").await;
                                continue;
                            }
                        };
                        let program_artifact = Artifact {
                            id: program_artifact_id.clone(),
                            label: "program".to_string(),
                            expiry: None,
                        };
                        let program: Vec<u8> = match program_artifact.download_program_from_uri(&request.program_public_uri).await {
                            Ok(p) => p,
                            Err(e) => {
                                error!("{SERIAL_PROVER_TAG} Failed to download program for request {}: {:?}. Marking as failed.", request_id_hex, e);
                                report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "program download failure").await;
                                continue;
                            }
                        };
                        info!(program_size = %program.len(), artifact_id = %hex::encode(program_artifact_id), "{SERIAL_PROVER_TAG} Downloaded program for {}.", request_id_hex);

                        // Download the stdin.
                        let stdin_artifact_id = match parse_artifact_id_from_url(&request.stdin_public_uri) {
                             Ok(id) => id,
                             Err(e) => {
                                error!("{SERIAL_PROVER_TAG} Failed to parse stdin URI for request {}: {:?}. Marking as failed.", request_id_hex, e);
                                report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "stdin URI parse failure").await;
                                continue;
                            }
                        };
                        let stdin_artifact = Artifact {
                            id: stdin_artifact_id.clone(),
                            label: "stdin".to_string(),
                            expiry: None,
                        };
                        let stdin: SP1Stdin = match stdin_artifact.download_stdin_from_uri(&request.stdin_public_uri).await {
                            Ok(s) => s,
                            Err(e) => {
                                error!("{SERIAL_PROVER_TAG} Failed to download stdin for request {}: {:?}. Marking as failed.", request_id_hex, e);
                                report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "stdin download failure").await;
                                continue;
                            }
                        };
                        info!(stdin_size = %stdin.buffer.iter().map(std::vec::Vec::len).sum::<usize>(), artifact_id = %hex::encode(stdin_artifact_id), "{SERIAL_PROVER_TAG} Downloaded stdin for {}.", request_id_hex);


                        // Generate the proving keys and the proof in a separate thread to catch panics.
                        let prover_clone = self.prover.clone();
                        let mode = ProofMode::try_from(request.mode).unwrap_or(ProofMode::Core);
                        let internal_mode = match mode {
                            ProofMode::Core => SP1ProofMode::Core,
                            ProofMode::Compressed => SP1ProofMode::Compressed,
                            ProofMode::Plonk => SP1ProofMode::Plonk,
                            ProofMode::Groth16 => SP1ProofMode::Groth16,
                            ProofMode::UnspecifiedProofMode => {
                                error!("{SERIAL_PROVER_TAG} Unspecified proof mode for request {}. Marking as failed.", request_id_hex);
                                report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "unspecified proof mode").await;
                                continue;
                            }
                        };

                        let proving_handle = tokio::task::spawn_blocking(move || {
                            panic::catch_unwind(AssertUnwindSafe(move || {
                                let start_setup = Instant::now();
                                info!("{SERIAL_PROVER_TAG} Setting up proving key for {}...", request_id_hex);
                                let (pk, _) = prover_clone.setup(&program);
                                info!(duration = %start_setup.elapsed().as_secs_f64(), "{SERIAL_PROVER_TAG} Set up proving key for {}.", request_id_hex);

                                let start_exec = Instant::now();
                                info!("{SERIAL_PROVER_TAG} Executing program for {}...", request_id_hex);
                                let exec_result = prover_clone.execute(&pk.elf, &stdin).run();
                                let report = match exec_result {
                                    Ok((_, r)) => r,
                                    Err(e) => {
                                        // This error needs to be propagated out of the catch_unwind
                                        return Err(anyhow::anyhow!("Execution failed for {}: {:?}", request_id_hex, e));
                                    }
                                };
                                let cycles = report.total_instruction_count();
                                info!(duration = %start_exec.elapsed().as_secs_f64(), cycles = %cycles, "{SERIAL_PROVER_TAG} Executed program for {}.", request_id_hex);

                                let start_prove = Instant::now();
                                info!("{SERIAL_PROVER_TAG} Generating proof for {} (mode: {:?})...", request_id_hex, internal_mode);
                                let proof = prover_clone.prove(&pk, &stdin).mode(internal_mode).run(); // Pass internal_mode
                                let proving_time = start_prove.elapsed();
                                info!(duration = %proving_time.as_secs_f64(), cycles = %cycles, "{SERIAL_PROVER_TAG} Proof generation complete for {}.", request_id_hex);
                                Ok((proof, cycles, proving_time)) // Return Ok result here
                            }))
                        });
                        let proving_abort_handle = proving_handle.abort_handle();

                        // Create a check task for this specific request.
                        let unexecutable_registry_clone = self.unexecutable_requests.clone();
                        let request_id_monitor = request_id_for_processing.clone();

                        let monitoring_task = tokio::spawn(async move {
                            let mut interval = tokio::time::interval(std::time::Duration::from_secs(2));
                            loop {
                                interval.tick().await;
                                let is_unexecutable = {
                                    let registry = unexecutable_registry_clone.lock().await;
                                    registry.contains(&request_id_monitor)
                                };
                                if is_unexecutable {
                                    info!(request_id = %hex::encode(&request_id_monitor), "{SERIAL_PROVER_TAG} Request now marked as UNEXECUTABLE, aborting proof generation");
                                    proving_abort_handle.abort();
                                    info!("{SERIAL_PROVER_TAG} Aborted proving task for {}.", hex::encode(&request_id_monitor));
                                    break;
                                }
                            }
                        });

                        let result = proving_handle.await;
                        monitoring_task.abort(); // Ensure monitor task is cleaned up

                        match result {
                            Ok(panic_result) => match panic_result {
                                Ok(Ok((proof_result, cycles, proving_time))) => { // Inner Ok for the result of execution and proving
                                    match proof_result {
                                        Ok(proof) => {
                                            let metrics = ctx.metrics();
                                            *metrics.total_cycles.lock().await += cycles;
                                            *metrics.total_proving_time.lock().await += proving_time;
                                            *metrics.fulfilled.lock().await += 1;

                                            let proof_bytes = match bincode::serialize(&proof) {
                                                Ok(pb) => pb,
                                                Err(e) => {
                                                    error!("{SERIAL_PROVER_TAG} Failed to serialize proof for {}: {:?}", request_id_hex, e);
                                                    report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "proof serialization failure").await;
                                                    continue; // Next message from stream
                                                }
                                            };

                                            let address = ctx.signer().address().to_vec();
                                            if let Err(e) = ctx.network().clone().with_retry(
                                                || async {
                                                    let nonce = ctx.network().clone().get_nonce(GetNonceRequest { address: address.clone() }).await?.into_inner().nonce;
                                                    // info!(nonce = %nonce, "{SERIAL_PROVER_TAG} Fetched account nonce for fulfilling {}.", request_id_hex);
                                                    let body = FulfillProofRequestBody {
                                                        nonce,
                                                        request_id: request_id_for_processing.clone(),
                                                        proof: proof_bytes.clone(),
                                                        reserved_metadata: None,
                                                    };
                                                    let fulfill_request = FulfillProofRequest {
                                                        format: MessageFormat::Binary.into(),
                                                        signature: body.sign(&ctx.signer()).into(),
                                                        body: Some(body),
                                                    };
                                                    ctx.network().clone().fulfill_proof(fulfill_request).await?;
                                                    info!(request_id = %request_id_hex, proof_size = %proof_bytes.len(), "{SERIAL_PROVER_TAG} Proof fulfillment submitted for {}.", request_id_hex);
                                                    Ok(())
                                                },
                                                "Fulfill",
                                            ).await {
                                                error!("{SERIAL_PROVER_TAG} Failed to fulfill proof for {}: {:?}", request_id_hex, e);
                                                // Failure to fulfill is critical, but the proof was generated.
                                                // The request remains assigned. The node might retry later or operator needs to check.
                                            }
                                        }
                                        Err(e) => { // Error from prover.prove() or prover.execute()
                                            error!("{SERIAL_PROVER_TAG} Proof generation failed for {}: {:?}", request_id_hex, e);
                                            report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "proof generation failure").await;
                                        }
                                    }
                                }
                                Ok(Err(e)) => { // Error explicitly returned from AssertUnwindSafe block (e.g. execute error)
                                    error!("{SERIAL_PROVER_TAG} Proving process failed for {}: {:?}", request_id_hex, e);
                                    report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "proving process internal failure").await;
                                }
                                Err(e) => { // Panic occurred
                                    let panic_msg = match e.downcast_ref::<&str>() {
                                        Some(s) => (*s).to_string(),
                                        None => match e.downcast_ref::<String>() {
                                            Some(s) => s.clone(),
                                            None => "Unknown panic".to_string(),
                                        },
                                    };
                                    error!("{SERIAL_PROVER_TAG} Proving panicked for {}: {}", request_id_hex, panic_msg);
                                    report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, "panic failure").await;
                                }
                            },
                            Err(e) => { // Task join error (e.g., aborted)
                                let is_cancelled = e.is_cancelled();
                                if is_cancelled {
                                    warn!(request_id = %request_id_hex, "{SERIAL_PROVER_TAG} Proving was aborted for {} (likely due to UNEXECUTABLE)", request_id_hex);
                                } else {
                                    error!("{SERIAL_PROVER_TAG} Proving task for {} was aborted unexpectedly: {:?}", request_id_hex, e);
                                }
                                report_request_status(ctx.as_ref(), request_id_for_processing, &request_id_for_processing, if is_cancelled { "aborted (unexecutable)" } else { "task join error" }).await;
                            }
                        }
                        // After processing one request (success or failure), we are ready for the next from the stream.
                        // The serial nature is maintained by only processing one at a time.
                    }
                    Ok(None) => {
                        warn!("{SERIAL_PROVER_TAG} Assigned requests stream ended cleanly. Reconnecting in {}s...", STREAM_CLEAN_END_RECONNECT_SECONDS);
                        time::sleep(Duration::from_secs(STREAM_CLEAN_END_RECONNECT_SECONDS)).await;
                        break 'request_processing_loop; // Break inner loop to re-establish stream
                    }
                    Err(e) => {
                        error!("{SERIAL_PROVER_TAG} Error receiving from assigned requests stream: {:?}. Reconnecting in {}s...", e, STREAM_ERROR_RECONNECT_SECONDS);
                        time::sleep(Duration::from_secs(STREAM_ERROR_RECONNECT_SECONDS)).await;
                        break 'request_processing_loop; // Break inner loop to re-establish stream
                    }
                }
            } // End of inner stream processing loop
        } // End of outer service loop (for stream reconnection)
    }
}

/// Helper function to report a request status to the network and log the result.
/// This handles both success and failure of the reporting itself.
async fn report_request_status<C: NodeContext>(
    ctx: &C,
    request_id: Vec<u8>,
    display_request_id: &[u8],
    status_type: &str,
) {
    const SERIAL_PROVER_TAG: &str = "\x1b[33m[SerialProver]\x1b[0m";

    if let Err(fail_err) = fail_request(ctx, request_id).await {
        error!(
            request_id = %hex::encode(display_request_id),
            "{SERIAL_PROVER_TAG} Failed to notify network about {} status: {:?}",
            status_type,
            fail_err
        );
    } else {
        info!(
            request_id = %hex::encode(display_request_id),
            "{SERIAL_PROVER_TAG} Successfully reported {} status to network",
            status_type
        );
    }
}
