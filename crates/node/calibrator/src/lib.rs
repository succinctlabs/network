#![deny(clippy::pedantic)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::similar_names)]
#![allow(clippy::items_after_statements)]
#![allow(clippy::missing_errors_doc)]
#![allow(clippy::cast_precision_loss)]

use anyhow::Result;
use sp1_sdk::{ProveRequest, Prover, ProvingKey, ProverClient, SP1Stdin};
use tracing::error;

/// Trait for calibrating the prover.
#[async_trait::async_trait]
pub trait Calibrator {
    /// Calibrate the prover.
    async fn calibrate(&self) -> Result<CalibratorMetrics>;
}

/// Metrics for the calibration of the prover.
#[derive(Debug, Clone, Copy, Default)]
pub struct CalibratorMetrics {
    /// The prover gas per second that the prover can process.
    pub pgus_per_second: f64,
    /// The recommended bid amount for the prover.
    pub pgu_price: f64,
}

/// The default implementation of a calibrator.
#[derive(Debug, Clone)]
pub struct SinglePassCalibrator {
    /// The ELF to use for the calibration.
    pub elf: Vec<u8>,
    /// The input stream to use for the calibration.
    pub stdin: SP1Stdin,
    /// The cost per hour of the instance (USD).
    pub cost_per_hour: f64,
    /// The expected average utilization rate of the instance.
    pub utilization_rate: f64,
    /// The target profit margin for the prover.
    pub profit_margin: f64,
}

impl SinglePassCalibrator {
    /// Create a new [`SinglePassCalibrator`].
    #[must_use]
    pub fn new(
        elf: Vec<u8>,
        stdin: SP1Stdin,
        cost_per_hour: f64,
        utilization_rate: f64,
        profit_margin: f64,
    ) -> Self {
        Self { elf, stdin, cost_per_hour, utilization_rate, profit_margin }
    }
}

#[async_trait::async_trait]
impl Calibrator for SinglePassCalibrator {
    async fn calibrate(&self) -> Result<CalibratorMetrics> {
        // Initialize the prover client from environment.
        let client = ProverClient::from_env().await;

        // Setup the proving key.
        let pk = client.setup(self.elf.clone().into()).await.map_err(|e| {
            error!("Failed to setup the prover: {e}");
            anyhow::anyhow!("{e}")
        })?;

        // Execute to get the prover gas.
        let (_, report) = client.execute(pk.elf().clone(), self.stdin.clone()).await.map_err(|e| {
            error!("Failed to execute the prover: {e}");
            anyhow::anyhow!("{e}")
        })?;
        let prover_gas = report.gas().unwrap_or(0);

        // Start timing.
        let start = std::time::Instant::now();

        // Generate the proof.
        let _ = client.prove(&pk, self.stdin.clone()).compressed().await.map_err(|e| {
            error!("Failed to generate the proof: {e}");
            anyhow::anyhow!("{e}")
        })?;

        // Calculate duration and throughput.
        let duration = start.elapsed();
        let pgus_per_second = prover_gas as f64 / duration.as_secs_f64();

        // Calculate the price per pgu using a simple economic model..
        //
        // The economic model is based on the following assumptions:
        // - The prover has a consistent cost per hour.
        // - The prover has a consistent utilization rate.
        // - The prover wants to maximize its profit.
        //
        // The model is based on the following formula:
        //
        // bidPricePerPGU = (costPerHour / averageUtilizationRate) * (1 + profitMargin) /
        // maxThroughputPerHour
        let pgus_per_hour = pgus_per_second * 3600.0;
        let utilized_pgus_per_hour = pgus_per_hour * self.utilization_rate;
        let optimal_pgu_price = self.cost_per_hour / utilized_pgus_per_hour;
        let pgu_price = optimal_pgu_price * (1.0 + self.profit_margin);

        // Return the metrics.
        Ok(CalibratorMetrics { pgus_per_second, pgu_price })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sp1_sdk::{include_elf, Elf};

    const SPN_FIBONACCI_ELF: Elf = include_elf!("spn-fibonacci-program");

    #[tokio::test]
    async fn test_calibrate() {
        // Create the ELF.
        let elf = SPN_FIBONACCI_ELF.to_vec();

        // Create the input stream.
        let n: u64 = 20;
        let mut stdin = SP1Stdin::new();
        stdin.write(&n);

        // Create the calibrator.
        let cost_per_hour = 0.1;
        let utilization_rate = 0.5;
        let profit_margin = 0.1;
        let calibrator =
            SinglePassCalibrator::new(elf, stdin, cost_per_hour, utilization_rate, profit_margin);

        // Calibrate the prover.
        let metrics = calibrator.calibrate().await.unwrap();
        println!("metrics: {metrics:?}");
    }
}
