use std::{process::Command, sync::Arc, time::Duration};

use alloy_signer_local::PrivateKeySigner;
use tokio::time::sleep;
use tonic::transport::Channel;
use tracing::{debug, error, info};

use sp1_prover::components::CpuProverComponents;
use sp1_sdk::{Prover as SP1Prover, ProverClient, SP1_CIRCUIT_VERSION};
use spn_network_types::prover_network_client::ProverNetworkClient;

mod balance;
mod bid;
pub mod config;
mod error;
pub mod grpc;
mod network;
mod prove;
mod retry;

// How frequently to check for new requests.
const REFRESH_INTERVAL_SEC: u64 = 3;

// The maximum number of requests to handle per loop.
//
// Currently, the CUDA prover can only handle one request at a time.
const REQUEST_LIMIT: u32 = 1;

// The version of SP1 to use.
const VERSION: &str = const_str::concat!("sp1-", SP1_CIRCUIT_VERSION);

// The explorer URL for individual requests.
const EXPLORER_URL_REQUEST: &str = "https://testnet.succinct.xyz/explorer/request";

/// Bids on new requests and proves assigned ones.
#[derive(Clone)]
pub struct Prover {
    network: ProverNetworkClient<Channel>,
    signer: PrivateKeySigner,
    sp1: Arc<Box<dyn SP1Prover<CpuProverComponents>>>,
    s3_bucket: String,
    s3_region: String,
}

impl Prover {
    /// Create a new Prover instance, checking for CUDA support.
    pub fn new(
        network: ProverNetworkClient<Channel>,
        signer: PrivateKeySigner,
        s3_bucket: &str,
        s3_region: &str,
    ) -> Self {
        let sp1: Box<dyn SP1Prover<CpuProverComponents>> = if Self::has_cuda_support() {
            info!("🚀 CUDA support detected, using GPU prover");
            Box::new(ProverClient::builder().cuda().build())
        } else {
            info!("💻 no CUDA support detected, using CPU prover");
            Box::new(ProverClient::builder().cpu().build())
        };

        Self {
            network,
            signer,
            sp1: Arc::new(sp1),
            s3_bucket: s3_bucket.to_string(),
            s3_region: s3_region.to_string(),
        }
    }

    /// Check if CUDA is available by testing if nvidia-smi is installed and CUDA GPUs are present.
    fn has_cuda_support() -> bool {
        // Common paths where nvidia-smi might be installed.
        let nvidia_smi_paths = ["nvidia-smi", "/usr/bin/nvidia-smi", "/usr/local/bin/nvidia-smi"];

        for path in nvidia_smi_paths {
            match Command::new(path).output() {
                Ok(output) => {
                    if output.status.success() {
                        debug!("found working nvidia-smi at: {}", path);
                        return true;
                    } else {
                        debug!("nvidia-smi at {} exists but returned error status", path);
                    }
                }
                Err(e) => {
                    debug!("failed to execute nvidia-smi at {}: {}", path, e);
                }
            }
        }

        debug!("no working nvidia-smi found in any standard location");
        false
    }

    /// Run the main loop which periodically checks for requests that can be bid on, and proves
    /// requests that we have won the auction for.
    pub async fn run(self) {
        info!("🔑 using account {}", self.signer.address());

        let this = Arc::new(self);

        // Check the balance to see if it can prove.
        if !balance::has_enough(Arc::clone(&this)).await.expect("failed to check balance") {
            error!("❌ not enough balance to prove, please fund your account");
            return;
        }
        // Get the owner (returns the signer address if this address is not delegated).
        let owner = balance::owner(Arc::clone(&this)).await.expect("failed to get owner");

        info!("🟢 ready to prove for 0x{}", hex::encode(&owner));

        loop {
            let bid_future = bid::process_requests(Arc::clone(&this), &owner);
            let prove_future = prove::process_requests(Arc::clone(&this), &owner);
            let _ = tokio::join!(bid_future, prove_future);

            sleep(Duration::from_secs(REFRESH_INTERVAL_SEC)).await;
        }
    }
}
