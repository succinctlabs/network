#![deny(clippy::pedantic)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::similar_names)]
#![allow(clippy::items_after_statements)]

use std::str::FromStr;

use alloy_primitives::{Address, U256};
use alloy_signer_local::PrivateKeySigner;
use anyhow::{anyhow, Result};
use clap::Parser;
use rustls::crypto::ring;
use tabled::{settings::Style, Table, Tabled};
use tracing::info;

use sp1_sdk::{include_elf, SP1Stdin};
use spn_calibrator::{Calibrator, SinglePassCalibrator};
use spn_network_types::prover_network_client::ProverNetworkClient;
use spn_node_core::{Node, NodeContext, SerialBidder, SerialContext, SerialMonitor, SerialProver};

/// The CLI application that defines all available commands.
#[derive(Parser)]
#[command(author, version, about, long_about = None)]
enum Args {
    /// Calibrate the prover.
    Calibrate(CalibrateArgs),
    /// Run the prover with previously benchmarked parameters.  
    Prove(ProveArgs),
}

/// The arguments for the `calibrate` command.
#[derive(Debug, Clone, Parser)]
struct CalibrateArgs {
    /// The cost per hour of the prover in USD.
    #[arg(long, help = "Cost per hour in USD, e.g. 0.80")]
    usd_cost_per_hour: f64,
    /// The expected utilization rate of the prover.
    #[arg(long, help = "Expected utilization rate, e.g. 0.5")]
    utilization_rate: f64,
    /// The target profit margin of the prover.
    #[arg(long, help = "Target profit margin, e.g. 0.1")]
    profit_margin: f64,
    /// The price of $PROVE in USD.
    #[arg(long, help = "Price of $PROVE in USD, e.g. 1.00")]
    prove_price: f64,
}

/// The arguments for the `prove` command.
#[derive(Debug, Clone, Parser)]
struct ProveArgs {
    /// The RPC URL for the network.
    #[arg(long)]
    rpc_url: String,
    /// The amount of proving gas units (PGUs) per second your prover can process.
    #[arg(long)]
    throughput: f64,
    /// The $PROVE price per billion proving gas units (PGUs) your prover is willing to bid.
    #[arg(long)]
    bid: f64,
    /// The private key for the prover.
    #[arg(long)]
    private_key: String,
    /// The address of the prover.
    #[arg(long)]
    prover: Address,
}

/// The main entry point for the CLI.
#[tokio::main]
async fn main() -> Result<()> {
    // Setup ring.
    ring::default_provider().install_default().expect("failed to install rustls crypto provider.");

    // Parse the arguments.
    let cli = Args::parse();

    // Print the header.
    let header = include_str!("./header.txt");
    println!("{header}");

    // Run the command.
    match cli {
        Args::Calibrate(args) => {
            // Create the ELF.
            const SPN_FIBONACCI_ELF: &[u8] = include_elf!("spn-fibonacci-program");

            // Create a table for the input parameters.
            #[derive(Tabled)]
            struct ParametersTable {
                #[tabled(rename = "Parameter")]
                name: String,
                #[tabled(rename = "Value")]
                value: String,
            }

            // Create parameters table data.
            let params_data = vec![
                ParametersTable {
                    name: "USD Cost Per Hour".to_string(),
                    value: format!("${:.2}", args.usd_cost_per_hour),
                },
                ParametersTable {
                    name: "Utilization Rate".to_string(),
                    value: format!("{:.2}%", args.utilization_rate * 100.0),
                },
                ParametersTable {
                    name: "Profit Margin".to_string(),
                    value: format!("{:.2}%", args.profit_margin * 100.0),
                },
                ParametersTable {
                    name: "USD Price of $PROVE".to_string(),
                    value: format!("${:.2}", args.prove_price),
                },
            ];

            // Create and style the parameters table.
            let mut params_table = Table::new(params_data);
            params_table.with(Style::modern());

            // Print parameters with a title.
            println!("\nParameters:");
            println!("{params_table}\n");

            // Create the input stream.
            let n: u64 = 20;
            let mut stdin = SP1Stdin::new();
            stdin.write(&n);

            // Run the calibrator to get the metrics.
            println!("Starting calibration...");
            let calibrator = SinglePassCalibrator::new(
                SPN_FIBONACCI_ELF.to_vec(),
                stdin,
                args.usd_cost_per_hour,
                args.utilization_rate,
                args.profit_margin,
            );
            let metrics =
                calibrator.calibrate().map_err(|e| anyhow!("failed to calibrate: {}", e))?;

            // Create a table for the calibration results.
            #[derive(Tabled)]
            struct CalibrationResultsTable {
                #[tabled(rename = "Metric")]
                name: String,
                #[tabled(rename = "Value")]
                value: String,
            }

            // Create results table data.
            let pgus_per_second = metrics.pgus_per_second.round();
            let results_data = vec![
                CalibrationResultsTable {
                    name: "Estimated Throughput".to_string(),
                    value: format!("{pgus_per_second} PGUs/second"),
                },
                CalibrationResultsTable {
                    name: "Estimated Bid Price".to_string(),
                    value: format!(
                        "{:.2} $PROVE per 1B PGUs",
                        metrics.pgu_price * args.prove_price * 1_000_000_000.0
                    ),
                },
            ];

            // Create and style the results table.
            let mut results_table = Table::new(results_data);
            results_table.with(Style::modern());

            // Print results with a title.
            println!("\nCalibration Results:");
            println!("{results_table}\n");
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
            let bidder = SerialBidder::new(U256::from(args.bid), args.throughput, args.prover);

            // Setup the prover
            let prover = SerialProver::new();

            // Setup the monitor.
            let monitor = SerialMonitor::new();

            // Setup the node.
            info!(
                wallet = %ctx.signer().address(),
                rpc = %args.rpc_url,
                throughput = %args.throughput,
                bid = %args.bid,
                "Starting Node on Succinct Network..."
            );
            let node = Node::new(ctx, bidder, prover, monitor);

            // Run the node.
            node.run().await?;
        }
    }

    Ok(())
}
