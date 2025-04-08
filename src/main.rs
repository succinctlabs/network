use std::str::FromStr;

use alloy_signer_local::PrivateKeySigner;
use anyhow::Result;
use dotenv::dotenv;
use tokio::signal;
use tracing::{error, info, warn};
use rustls::crypto::CryptoProvider;

use spn_network_types::prover_network_client::ProverNetworkClient;
use spn_prover::{config::Settings, grpc, Prover};

#[tokio::main]
async fn main() -> Result<()> {
    // Load environment variables.
    dotenv().ok();

    // Load configuration
    let settings = Settings::new()?;

    // Initialize logging with minimal format for the prover binary
    spn_logging::init(settings.log_format);

    // Install the default CryptoProvider
    rustls::crypto::ring::default_provider().install_default().expect("Failed to install rustls crypto provider");

    // Initialize the dependencies.
    let network_channel = grpc::configure_endpoint(settings.rpc_url.clone())?.connect().await?;
    let network = ProverNetworkClient::new(network_channel);
    let signer = PrivateKeySigner::from_str(&settings.private_key)?;

    // Initialize the prover.
    let prover = Prover::new(network, signer, &settings.s3_bucket, &settings.s3_region);

    // Spawn the prover task.
    let mut prover_handle = Some(tokio::spawn(async move {
        prover.run().await;
    }));

    // Wait for the tasks to finish or a signal to shutdown.
    tokio::select! {
        _ = prover_handle.as_mut().unwrap() => {
            error!("prover task exited unexpectedly");
        }
        _ = signal::ctrl_c() => {
            warn!("ctrl-c received, shutting down");
        }
    }

    // Abort the tasks if they're still running.
    if let Some(handle) = prover_handle.take() {
        handle.abort();
        let _ = handle.await;
    }
    info!("graceful shutdown complete");

    Ok(())
}
