use clap::Parser;
use anyhow::Result;
use spn_prover_core::prove;

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

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match &cli.command {
        Commands::Prove { worst_case_throughput, bid_amount } => {
            // Call the prover's main function with the parameters.
            prove(*worst_case_throughput, *bid_amount).await?;
        }
    }

    Ok(())
} 