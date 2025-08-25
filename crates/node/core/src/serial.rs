use std::{
    collections::HashSet,
    env,
    panic::{self, AssertUnwindSafe},
    sync::{atomic, Arc},
    time::{Duration, Instant, SystemTime},
};

use alloy_primitives::{Address, U256};
use alloy_signer_local::PrivateKeySigner;
use anyhow::{Context, Result};
use chrono::{self, DateTime};
use nvml_wrapper::Nvml;
use sp1_sdk::{EnvProver, SP1ProofMode, SP1Stdin};
use spn_artifacts::{extract_artifact_name, Artifact};
use spn_network_types::{
    prover_network_client::ProverNetworkClient, BidRequest, BidRequestBody, ExecutionStatus,
    FailFulfillmentRequest, FailFulfillmentRequestBody, FulfillProofRequest,
    FulfillProofRequestBody, FulfillmentStatus, GetFilteredProofRequestsRequest, GetNonceRequest,
    GetProofRequestDetailsRequest, MessageFormat, ProofMode, Signable, TransactionVariant,
};
use spn_rpc::{fetch_owner, RetryableRpc};
use spn_utils::{time_now, SPN_MAINNET_V1_DOMAIN};
use sysinfo::{CpuExt, System, SystemExt};
use tokio::sync::Mutex;
use tonic::{async_trait, transport::Channel};
use tracing::{error, info, warn};

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
    /// The $PROVE price per billion proving gas units (PGUs) for the bidder.
    pub bid: U256,
    /// The throughput for the prover in proving gas units (PGUs) per second.
    pub throughput: f64,
    /// The prover we are bidding on behalf of.
    pub prover: Address,
}

impl SerialBidder {
    /// Create a new [`SerialBidder`].
    #[must_use]
    pub fn new(bid: U256, throughput: f64, prover: Address) -> Self {
        Self { bid, throughput, prover }
    }
}

#[async_trait]
impl<C: NodeContext> NodeBidder<C> for SerialBidder {
    #[allow(clippy::too_many_lines)]
    async fn bid(&self, ctx: &C) -> Result<()> {
        const SERIAL_BIDDER_TAG: &str = "\x1b[34m[SerialBidder]\x1b[0m";

        // Fetch the owner.
        let signer = ctx.signer().address().to_vec();
        let owner = fetch_owner(ctx.network(), &signer).await?;
        info!(owner = %hex::encode(&owner), signer = %hex::encode(&signer), "{SERIAL_BIDDER_TAG} Fetched owner.");

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
                        program_uri = %request.program_public_uri,
                        stdin_uri = %request.stdin_public_uri,
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
                    info!(request_id = %request_id, bid = %self.bid, "{SERIAL_BIDDER_TAG} Submitting a bid for request");
                    let body = BidRequestBody {
                        nonce,
                        request_id: hex::decode(request_id.clone())
                            .context("failed to decode request_id")?,
                        amount: self.bid.to_string(),
                        prover: self.prover.to_vec(),
                        domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
                        variant: TransactionVariant::BidVariant as i32,
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
        }

        Self {
            prover: Arc::new(EnvProver::new()),
            unexecutable_requests: Arc::new(Mutex::new(HashSet::new())),
        }
    }

    /// Checks the network for unexecutable requests and maintains a registry.
    fn ensure_unexecutable_check_task_running<C: NodeContext>(&self, ctx: &C) {
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
        let unexecutable_requests = self.unexecutable_requests.clone();
        let network = ctx.network().clone();
        let signer_address = ctx.signer().address().to_vec();

        // Spawn a background task to check for unexecutable requests.
        tokio::spawn(async move {
            const SERIAL_PROVER_TAG: &str = "\x1b[33m[SerialProver]\x1b[0m";

            loop {
                // Fetch the owner.
                let owner = match fetch_owner(&network, &signer_address).await {
                    Ok(owner) => owner,
                    Err(e) => {
                        tracing::warn!("{SERIAL_PROVER_TAG} Failed to fetch owner: {:?}", e);
                        tokio::time::sleep(Duration::from_secs(5)).await;
                        continue;
                    }
                };

                // Check for unexecutable requests.
                let response = match network
                    .clone()
                    .get_filtered_proof_requests(GetFilteredProofRequestsRequest {
                        version: Some(SP1_NETWORK_VERSION.to_string()),
                        fulfillment_status: Some(FulfillmentStatus::Assigned.into()),
                        execution_status: Some(ExecutionStatus::Unexecutable.into()),
                        fulfiller: Some(owner),
                        limit: Some(100),
                        ..Default::default()
                    })
                    .await
                {
                    Ok(resp) => resp.into_inner(),
                    Err(e) => {
                        tracing::warn!(
                            "{SERIAL_PROVER_TAG} Failed to check for unexecutable requests: {:?}",
                            e
                        );
                        tokio::time::sleep(Duration::from_secs(5)).await;
                        continue;
                    }
                };

                // Update the registry with unexecutable request IDs.
                let mut registry = unexecutable_requests.lock().await;
                for request in response.requests {
                    let request_id_hex = hex::encode(&request.request_id);
                    if registry.insert(request.request_id) {
                        // Only log if this is a new insertion.
                        tracing::info!(
                            request_id = %request_id_hex,
                            "{SERIAL_PROVER_TAG} Added request to unexecutable registry"
                        );
                    }
                }

                // Sleep for a bit before checking again.
                tokio::time::sleep(Duration::from_secs(5)).await;
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
                let body = FailFulfillmentRequestBody {
                    nonce,
                    request_id: request_id.clone(),
                    error: None,
                };
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
    async fn prove(&self, ctx: &C) -> Result<()> {
        const SERIAL_PROVER_TAG: &str = "\x1b[33m[SerialProver]\x1b[0m";

        // Ensure the background check task is running.
        self.ensure_unexecutable_check_task_running(ctx);

        // Fetch the owner.
        let signer = ctx.signer().address().to_vec();
        let owner = fetch_owner(ctx.network(), &signer).await?;
        info!(owner = %hex::encode(&owner), signer = %hex::encode(&signer), "{SERIAL_PROVER_TAG} Fetched owner.");

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
            // Check if this request is already known to be unexecutable.
            let request_id = request.request_id.clone();
            let unexecutable_registry = self.unexecutable_requests.lock().await;
            if unexecutable_registry.contains(&request_id) {
                info!(
                    request_id = %hex::encode(&request_id),
                    "{SERIAL_PROVER_TAG} Skipping request marked as UNEXECUTABLE"
                );

                // Release lock early.
                drop(unexecutable_registry);

                // Notify the network about the failure.
                report_request_status(ctx, request_id.clone(), &request_id, "skipped UNEXECUTABLE")
                    .await;

                continue;
            }

            // No longer need the registry lock.
            drop(unexecutable_registry);

            // Log the request details.
            let request_id_hex = hex::encode(&request.request_id);
            info!(
                request_id = %request_id_hex,
                vk_hash = %hex::encode(request.vk_hash),
                version = %request.version,
                mode = %request.mode,
                strategy = %request.strategy,
                requester = %hex::encode(request.requester),
                tx_hash = %hex::encode(request.tx_hash),
                program_uri = %request.program_public_uri,
                stdin_uri = %request.stdin_public_uri,
                cycle_limit = %request.cycle_limit,
                created_at = %request.created_at,
                created_at_utc = %DateTime::from_timestamp(i64::try_from(request.created_at).unwrap_or_default(), 0).unwrap_or_default(),
                deadline = %request.deadline,
                deadline_utc = %DateTime::from_timestamp(i64::try_from(request.deadline).unwrap_or_default(), 0).unwrap_or_default(),
                "{SERIAL_PROVER_TAG} Proving request..."
            );

            // Download the program.
            let program_artifact_id = extract_artifact_name(&request.program_public_uri)?;
            let program_artifact = Artifact {
                id: program_artifact_id.clone(),
                label: "program".to_string(),
                expiry: None,
            };
            let program: Vec<u8> =
                program_artifact.download_program_from_uri(&request.program_public_uri, "").await?;
            info!(program_size = %program.len(), artifact_id = %hex::encode(program_artifact_id), "{SERIAL_PROVER_TAG} Downloaded program.");

            // Download the stdin.
            let stdin_artifact_id = extract_artifact_name(&request.stdin_public_uri)?;
            let stdin_artifact = Artifact {
                id: stdin_artifact_id.clone(),
                label: "stdin".to_string(),
                expiry: None,
            };
            let stdin: SP1Stdin =
                stdin_artifact.download_stdin_from_uri(&request.stdin_public_uri, "").await?;
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

            // Store the join handle and extract its abort handle.
            let proving_handle = tokio::task::spawn_blocking(move || {
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
            });
            let proving_abort_handle = proving_handle.abort_handle();

            // Create a check task for this specific request.
            let request_id = request.request_id.clone();
            let unexecutable_registry = self.unexecutable_requests.clone();

            // Spawn a task to periodically check if the request became UNEXECUTABLE.
            let monitoring_task = tokio::spawn(async move {
                // Check every 2 seconds if the request is now in our unexecutable registry.
                let mut interval = tokio::time::interval(std::time::Duration::from_secs(2));
                loop {
                    interval.tick().await;

                    // Check if we already know this request is unexecutable.
                    let is_unexecutable = {
                        let registry = unexecutable_registry.lock().await;
                        registry.contains(&request_id)
                    };

                    if is_unexecutable {
                        info!(
                            request_id = %hex::encode(&request_id),
                            "{SERIAL_PROVER_TAG} Request now marked as UNEXECUTABLE, aborting proof generation"
                        );

                        // Abort the proving task.
                        proving_abort_handle.abort();

                        info!("{SERIAL_PROVER_TAG} Aborted proving task.");

                        break;
                    }
                }
            });

            // Wait for the proving task to complete or be aborted.
            let result = proving_handle.await;

            // Cancel the monitoring task since proving is done.
            monitoring_task.abort();

            match result {
                Ok(panic_result) => match panic_result {
                    Ok((proof_result, cycles, proving_time)) => {
                        match proof_result {
                            Ok(proof) => {
                                // Update the metrics.
                                let metrics = ctx.metrics();
                                *metrics.total_cycles.lock().await += cycles;
                                *metrics.total_proving_time.lock().await += proving_time;
                                *metrics.fulfilled.lock().await += 1;

                                // Now serialize the actual proof value
                                let proof_bytes = bincode::serialize(&proof)
                                    .context("failed to serialize proof")?;

                                // Fulfill the proof.
                                let address = ctx.signer().address().to_vec();
                                if let Err(e) = ctx.network()
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
                                                reserved_metadata: None,
                                                domain: SPN_MAINNET_V1_DOMAIN.to_vec(),
                                                variant: TransactionVariant::FulfillVariant as i32,
                                            };
                                            let fulfill_request = FulfillProofRequest {
                                                format: MessageFormat::Binary.into(),
                                                signature: body.sign(&ctx.signer()).into(),
                                                body: Some(body),
                                            };
                                            ctx.network().clone().fulfill_proof(fulfill_request).await?;
                                            info!(
                                                request_id = %hex::encode(&request.request_id),
                                                proof_size = %proof_bytes.len(),
                                                "{SERIAL_PROVER_TAG} Proof fulfillment submitted."
                                            );
                                            Ok(())
                                        },
                                        "Fulfill",
                                    )
                                    .await
                                {
                                    error!("{SERIAL_PROVER_TAG} Failed to fulfill proof: {:?}", e);
                                }
                            }
                            Err(e) => {
                                error!("{SERIAL_PROVER_TAG} Proof generation failed: {:?}", e);

                                // Report failure to the network
                                report_request_status(
                                    ctx,
                                    request.request_id.clone(),
                                    &request.request_id,
                                    "proof failure",
                                )
                                .await;
                            }
                        }
                    }
                    Err(e) => {
                        let panic_msg = match e.downcast_ref::<&str>() {
                            Some(s) => (*s).to_string(),
                            None => match e.downcast_ref::<String>() {
                                Some(s) => s.clone(),
                                None => "Unknown panic".to_string(),
                            },
                        };

                        error!("{SERIAL_PROVER_TAG} Proving panicked: {}", panic_msg);

                        // Attempt to mark the request as failed on the network.
                        report_request_status(
                            ctx,
                            request.request_id.clone(),
                            &request.request_id,
                            "panic failure",
                        )
                        .await;
                    }
                },
                Err(e) => {
                    // Check if this was a cancellation.
                    let is_cancelled = e.is_cancelled();

                    if is_cancelled {
                        warn!(
                            request_id = %hex::encode(&request.request_id),
                            "{SERIAL_PROVER_TAG} Proving was aborted because request is UNEXECUTABLE"
                        );
                    } else {
                        error!("{SERIAL_PROVER_TAG} Proving was aborted because: {:?}", e);
                    }

                    // Always notify network about task failure.
                    let status_type = if is_cancelled { "cancellation" } else { "task failure" };
                    report_request_status(
                        ctx,
                        request.request_id.clone(),
                        &request.request_id,
                        status_type,
                    )
                    .await;
                }
            }
        }

        Ok(())
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
