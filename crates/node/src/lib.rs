#![deny(clippy::pedantic)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::similar_names)]
#![allow(clippy::items_after_statements)]
#![allow(clippy::missing_errors_doc)]
#![allow(clippy::cast_precision_loss)]

mod serial;

use std::time::Duration;

use alloy_signer_local::PrivateKeySigner;
pub use serial::*;
use sp1_sdk::SP1_CIRCUIT_VERSION;
use spn_network_types::prover_network_client::ProverNetworkClient;
use tokio::time::sleep;
use tonic::{async_trait, transport::Channel};
use tracing::info;

/// The version identifier for SP1 used on the network.
pub const SP1_NETWORK_VERSION: &str = const_str::concat!("sp1-", SP1_CIRCUIT_VERSION);

/// The base URL for viewing requests on the network.
pub const EXPLORER_REQUEST_BASE_URL: &str = "https://testnet.succinct.xyz/explorer/request";

/// A node on the Succinct Prover Network.
///
/// It consists of a context, a bidder, and a prover. It periodically bids and proves requests based
/// on the provided configuration.
#[derive(Debug, Clone)]
pub struct Node<C, B, P> {
    /// The context for the node.
    pub ctx: C,
    /// The bidder for the node.
    pub bidder: B,
    /// The prover for the node.
    pub prover: P,
}

impl<C, B, P> Node<C, B, P> {
    /// Create a new [Node].
    pub fn new(ctx: C, bidder: B, prover: P) -> Self {
        Self { ctx, bidder, prover }
    }
}

/// The standard context for a node.
///
/// This is usually used to access shared state that can be extended across the node, bidder, and
/// the prover.
pub trait NodeContext: Send + Sync {
    /// The network client for the node.
    fn network(&self) -> &ProverNetworkClient<Channel>;
    /// The signer for the node.
    fn signer(&self) -> &PrivateKeySigner;
}

/// The bidder for a node.
///
/// The bidder is responsible for bidding on requests. The bidding logic gets periodically called by
/// the [Node].
#[async_trait]
pub trait NodeBidder<C> {
    /// Bid on requests.
    async fn bid(&self, ctx: &C) -> anyhow::Result<()>;
}

/// The prover for a node.
///
/// The prover is responsible for proving requests. The proving logic gets periodically called by
/// the [Node].
#[async_trait]
pub trait NodeProver<C> {
    /// Prove requests.
    async fn prove(&self, ctx: &C) -> anyhow::Result<()>;
}

impl<C: NodeContext, B: NodeBidder<C>, P: NodeProver<C>> Node<C, B, P> {
    /// Run the node.
    pub async fn run(self) -> anyhow::Result<()> {
        info!("🔑 using account {}.", self.ctx.signer().address());

        loop {
            self.bidder.bid(&self.ctx).await?;
            self.prover.prove(&self.ctx).await?;
            sleep(Duration::from_secs(3)).await;
        }
    }
}
