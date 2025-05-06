#![deny(clippy::pedantic)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::similar_names)]
#![allow(clippy::items_after_statements)]
#![allow(clippy::missing_errors_doc)]
#![allow(clippy::cast_precision_loss)]
#![allow(clippy::cast_sign_loss)]
#![allow(clippy::cast_possible_truncation)]

mod serial;

use std::{
    sync::Arc,
    time::{Duration, SystemTime},
};

use alloy_signer_local::PrivateKeySigner;
use anyhow::Result;
pub use serial::*;
use sp1_sdk::SP1_CIRCUIT_VERSION;
use spn_network_types::prover_network_client::ProverNetworkClient;
use tokio::{sync::Mutex, time::sleep};
use tonic::{async_trait, transport::Channel};

/// The version identifier for SP1 used on the network.
pub const SP1_NETWORK_VERSION: &str = const_str::concat!("sp1-", SP1_CIRCUIT_VERSION);

/// The base URL for viewing requests on the network.
pub const EXPLORER_REQUEST_BASE_URL: &str = "https://testnet.succinct.xyz/explorer/request";

/// A node on the Succinct Prover Network.
///
/// It consists of a context, a bidder, and a prover. It periodically bids and proves requests based
/// on the provided configuration.
#[derive(Debug)]
pub struct Node<C, B, P, M> {
    /// The context for the node.
    pub ctx: Arc<C>,
    /// The bidder for the node.
    pub bidder: Arc<B>,
    /// The prover for the node.
    pub prover: Arc<P>,
    /// The monitor for the node.
    pub monitor: Arc<M>,
}

impl<C, B, P, M> Node<C, B, P, M> {
    /// Create a new [Node].
    pub fn new(ctx: C, bidder: B, prover: P, metrics: M) -> Self {
        Self {
            ctx: Arc::new(ctx),
            bidder: Arc::new(bidder),
            prover: Arc::new(prover),
            monitor: Arc::new(metrics),
        }
    }
}

/// The standard context for a node.
///
/// This is usually used to access shared state that can be extended across the node, bidder, and
/// the prover.
pub trait NodeContext: Send + Sync + 'static {
    /// The network client for the node.
    fn network(&self) -> &ProverNetworkClient<Channel>;
    /// The signer for the node.
    fn signer(&self) -> &PrivateKeySigner;
    /// The metrics for the node.
    fn metrics(&self) -> &NodeMetrics;
}

/// The bidder for a node.
///
/// The bidder is responsible for bidding on requests. The bidding logic gets periodically called by
/// the [Node].
#[async_trait]
pub trait NodeBidder<C>: Send + Sync + 'static {
    /// Bid on requests.
    async fn bid(&self, ctx: &C) -> Result<()>;
}

/// The prover for a node.
///
/// The prover is responsible for proving requests. The proving logic gets periodically called by
/// the [Node].
#[async_trait]
pub trait NodeProver<C>: Send + Sync + 'static {
    /// Prove requests.
    async fn prove(&self, ctx: &C) -> Result<()>;
}

/// The monitor for a node.
///
/// The monitor is responsible for monitoring the node.
#[async_trait]
pub trait NodeMonitor<C>: Send + Sync + 'static {
    /// Collect metrics.
    async fn record(&self, ctx: &C) -> Result<()>;
}

/// The metrics for a node.
///
/// This is used to collect metrics from the node.
#[derive(Debug)]
pub struct NodeMetrics {
    /// The number of requests fulfilled.
    pub fulfilled: Mutex<u64>,
    /// The time the node was started.
    pub online_since: SystemTime,
    /// The total number of cycles the node has proven.
    pub total_cycles: Mutex<u64>,
    /// The total time the node has spent proving.
    pub total_proving_time: Mutex<Duration>,
}

impl<C: NodeContext, B: NodeBidder<C>, P: NodeProver<C>, M: NodeMonitor<C>> Node<C, B, P, M> {
    /// Run the node.
    pub async fn run(self) -> Result<()> {
        // Run the bid and prove task.
        let ctx = self.ctx.clone();
        let bidder = self.bidder.clone();
        let prover = self.prover.clone();
        let bid_and_prove_task = tokio::spawn(async move {
            let result: Result<()> = async {
                loop {
                    let bid_future = bidder.bid(&ctx);
                    let prove_future = prover.prove(&ctx);
                    let _ = tokio::join!(bid_future, prove_future);

                    sleep(Duration::from_secs(3)).await;
                }
            }
            .await;
            result
        });

        // Run the system monitor task.
        let ctx = self.ctx.clone();
        let monitor = self.monitor.clone();
        let monitor_task = tokio::spawn(async move {
            let result: Result<()> = async {
                loop {
                    monitor.record(&ctx).await?;
                    sleep(Duration::from_secs(30)).await;
                }
            }
            .await;
            result
        });

        // Wait until one of the tasks fails.
        tokio::select! {
            result = bid_and_prove_task => {
                if let Err(e) = result {
                    return Err(e.into());
                }
            },
            result = monitor_task => {
                if let Err(e) = result {
                    return Err(e.into());
                }
            },
        }

        Ok(())
    }
}
