use clap::Parser;
use anyhow::Result;
use prover_core::{Prover, config};
use rustls::crypto::ring;
use spn_logging::LogFormat;
use tonic::transport::Channel;
use spn_network_types::prover_network_client::ProverNetworkClient;
use alloy_signer_local::PrivateKeySigner;
use std::str::FromStr;

/// The main CLI structure that defines the available commands.
#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

/// The available commands that can be executed by the CLI.
#[derive(clap::Subcommand)]
enum Commands {
    /// Run the prover with required parameters.
    Prove {
        /// The worst case throughput in proofs/second.
        #[arg(long)]
        worst_case_throughput: f64,
        
        /// The bid amount in USDC.
        #[arg(long)]
        bid_amount: u64,
    },
}

/// The main entry point for the CLI.
#[tokio::main]
async fn main() -> Result<()> {
    // Install the default CryptoProvider.
    ring::default_provider().install_default().expect("Failed to install rustls crypto provider.");

    let cli = Cli::parse();

    match &cli.command {
        Commands::Prove { worst_case_throughput, bid_amount } => {
            let settings = config::Settings::new()?;
            
            // Initialize logging.
            spn_logging::init(settings.log_format);

            let endpoint = prover_core::grpc::configure_endpoint(settings.rpc_url)?;
            let network = ProverNetworkClient::connect(endpoint).await?;
            let signer = PrivateKeySigner::from_str(&settings.private_key)?;
            
            let prover = Prover::new(
                network,
                signer,
                &settings.s3_bucket,
                &settings.s3_region,
                *worst_case_throughput,
                *bid_amount,
            );
            
            prover.run().await;
        }
    }

    Ok(())
} 