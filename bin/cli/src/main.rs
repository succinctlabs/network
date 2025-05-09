#![deny(clippy::pedantic)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::similar_names)]
#![allow(clippy::items_after_statements)]

use std::str::FromStr;

use alloy_primitives::U256;
use alloy_signer_local::PrivateKeySigner;
use anyhow::{anyhow, Result};
use clap::Parser;
use rustls::crypto::ring;
use tabled::{settings::Style, Table, Tabled};
use tracing::info;

use sp1_sdk::{include_elf, SP1Stdin};
use spn_calibrator::{Calibrator, SinglePassCalibrator};
use spn_network_types::prover_network_client::ProverNetworkClient;
use spn_node::{Node, NodeContext, SerialBidder, SerialContext, SerialMonitor, SerialProver};

/// The CLI application that defines all available commands.
#[derive(Parser)]
#[command(author, version, about, long_about = None)]
enum Args {
    /// Calibrate the prover.
    Calibrate,
    /// Run the prover with previously benchmarked parameters.  
    Prove(ProveArgs),
}

/// The arguments for the `prove` command.
#[derive(Debug, Clone, Parser)]
struct ProveArgs {
    /// The RPC URL for the network.
    #[arg(long)]
    rpc_url: String,
    /// The estimated throughput of the prover.
    #[arg(long)]
    throughput: f64,
    /// The bid amount for the prover.
    #[arg(long)]
    bid_amount: u64,
    /// The private key for the prover.
    #[arg(long)]
    private_key: String,
}

/// The main entry point for the CLI.
#[tokio::main]
async fn main() -> Result<()> {
    // Setup ring.
    ring::default_provider().install_default().expect("failed to install rustls crypto provider.");

    // Print the header.
    println!("{}", include_str!("header.txt"));

    // Set the environment variables.
    std::env::set_var("DISABLE_SP1_CUDA_LOG", "1");
    std::env::set_var("RUST_LOG", "debug");
    std::env::set_var("SP1_PROVER", "cuda");

    // Parse the arguments.
    let cli = Args::parse();

    // Run the command.
    match cli {
        Args::Calibrate => {
            // Create the ELF.
            const SPN_FIBONACCI_ELF: &[u8] = include_elf!("spn-fibonacci-program");

            // Create the input stream.
            let n: u32 = 20;
            let mut stdin = SP1Stdin::new();
            stdin.write(&n);

            // Run the calibrator to get the metrics.
            let calibrator = SinglePassCalibrator::new(SPN_FIBONACCI_ELF.to_vec(), stdin);
            let metrics =
                calibrator.calibrate().map_err(|e| anyhow!("failed to calibrate: {}", e))?;

            // Create a table for the metrics.
            #[allow(clippy::items_after_statements)]
            #[derive(Tabled)]
            struct CalibrationMetricsTable {
                #[tabled(rename = "Metric")]
                name: String,
                #[tabled(rename = "Value")]
                value: String,
            }

            // Create table data.
            let data = vec![
                CalibrationMetricsTable {
                    name: "Prover Throughput".to_string(),
                    value: format!("{} gas/second", metrics.throughput),
                },
                CalibrationMetricsTable {
                    name: "Recommended Bid".to_string(),
                    value: format!("{} gas per USDC", metrics.bid_amount),
                },
            ];

            // Create and style the table.
            let mut table = Table::new(data);
            table.with(Style::modern());

            // Print with a title.
            println!("\nCalibration Results:");
            println!("{table}\n");

            // Print suggestion for next steps.
            println!("To start proving with these parameters, run:\n");
            println!("  spn prove --privateKey <privateKey> \\");
            println!("      --estimatedThroughput {} \\", metrics.throughput);
            println!("      --bidAmount {}\n", metrics.bid_amount);
        }
        Args::Prove(args) => {
            spn_utils::init_logger(spn_utils::LogFormat::Pretty);

            // Setup the connection to the network.
            let endpoint = spn_rpc::configure_endpoint(&args.rpc_url)?;
            let network = ProverNetworkClient::connect(endpoint).await?;

            // Setup the signer.
            let signer = PrivateKeySigner::from_str(&args.private_key)?;

            // Setup the context.
            let ctx = SerialContext::new(network, signer);

            // Setup the bidder.
            let bidder = SerialBidder::new(U256::from(args.bid_amount), args.throughput);

            // Setup the prover
            let prover = SerialProver::new();

            // Setup the monitor.
            let monitor = SerialMonitor;

            // Setup the node.
            info!(
                wallet = %ctx.signer().address(),
                rpc = %args.rpc_url,
                throughput = %args.throughput,
                bid_amount = %args.bid_amount,
                "Starting Node on Succinct Network..."
            );
            let node = Node::new(ctx, bidder, prover, monitor);

            // Run the node.
            node.run().await?;
        }
    }

    Ok(())
}
