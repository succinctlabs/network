use clap::Parser;
use anyhow::Result;
use prover_core::{Prover, config};
use benchmark::{has_cuda_support, run_benchmarks};
use rustls::crypto::ring;
use spn_logging::LogFormat;
use tonic::transport::Channel;
use spn_network_types::prover_network_client::ProverNetworkClient;
use alloy_signer_local::PrivateKeySigner;
use std::str::FromStr;
use std::env;
use std::fs;
use dotenv::dotenv;

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
    /// Initialize the prover with a private key and run benchmarks
    Init {
        /// The private key for the prover
        #[arg(long)]
        private_key: String,
    },
    /// Run the prover with previously benchmarked parameters
    Prove,
}

/// The main entry point for the CLI.
#[tokio::main]
async fn main() -> Result<()> {
    // Load environment variables from .env file
    dotenv().ok();

    // Install the default CryptoProvider.
    ring::default_provider().install_default().expect("Failed to install rustls crypto provider.");

    let cli = Cli::parse();

    match &cli.command {
        Commands::Init { private_key } => {
            // Run benchmarks to get throughput and bid amount
            let (worst_case_throughput, bid_amount) = run_benchmarks().await?;
            
            // Save environment variables
            let env_content = format!(
                r#"WORST_CASE_THROUGHPUT={}
BID_AMOUNT={}
PRIVATE_KEY={}
NETWORK_RPC_URL=https://rpc.testnet-private.succinct.xyz
NETWORK_LOG_FORMAT=Pretty
AWS_ACCESS_KEY_ID=AKIAWEFFNPGX7HNADYHT
AWS_SECRET_ACCESS_KEY=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
AWS_DEFAULT_REGION=us-east-2
S3_BUCKET=spn-prover"#,
                worst_case_throughput,
                bid_amount,
                private_key
            );
            
            // Write to .env file
            fs::write(".env", env_content)?;
            
            println!("Initialization complete. Environment variables saved to .env");
        }
        Commands::Prove => {
            let settings = config::Settings::new()?;
            
            // Initialize logging.
            spn_logging::init(settings.log_format);

            let endpoint = prover_core::grpc::configure_endpoint(settings.rpc_url)?;
            let network = ProverNetworkClient::connect(endpoint).await?;
            
            // Read environment variables
            let worst_case_throughput: f64 = env::var("WORST_CASE_THROUGHPUT")
                .expect("WORST_CASE_THROUGHPUT not set. Run 'spn init' first.")
                .parse()?;
            let bid_amount: u64 = env::var("BID_AMOUNT")
                .expect("BID_AMOUNT not set. Run 'spn init' first.")
                .parse()?;
            let private_key = env::var("PRIVATE_KEY")
                .expect("PRIVATE_KEY not set. Run 'spn init' first.");
            
            let signer = PrivateKeySigner::from_str(&private_key)?;
            
            let prover = Prover::new(
                network,
                signer,
                &settings.s3_bucket,
                &settings.s3_region,
                worst_case_throughput,
                bid_amount,
            );
            
            prover.run().await;
        }
    }

    Ok(())
} 