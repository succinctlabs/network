#![deny(clippy::pedantic)]
#![allow(clippy::module_name_repetitions)]
#![allow(clippy::similar_names)]
#![allow(clippy::items_after_statements)]
#![allow(clippy::missing_errors_doc)]
#![allow(clippy::cast_precision_loss)]

use sp1_sdk::{ProverClient, SP1Stdin};

/// Trait for calibrating the prover.
pub trait Calibrator {
    /// Calibrate the prover.
    fn calibrate(&self) -> CalibratorMetrics;
}

/// Metrics for the calibration of the prover.
#[derive(Debug, Clone, Copy, Default)]
pub struct CalibratorMetrics {
    /// The prover gas per second that the prover can process.
    pub throughput: f64,
    /// The recommended bid amount for the prover.
    pub bid_amount: u64,
}

/// The default implementation of a calibrator.
#[derive(Debug, Clone)]
pub struct SinglePassCalibrator {
    /// The ELF to use for the calibration.
    pub elf: Vec<u8>,
    /// The input stream to use for the calibration.
    pub stdin: SP1Stdin,
}

impl SinglePassCalibrator {
    /// Create a new [`SinglePassCalibrator`].
    #[must_use]
    pub fn new(elf: Vec<u8>, stdin: SP1Stdin) -> Self {
        Self { elf, stdin }
    }
}

impl Calibrator for SinglePassCalibrator {
    fn calibrate(&self) -> CalibratorMetrics {
        // Initialize the prover client from environment
        let client = ProverClient::from_env();

        // Execute to get the prover gas.
        let (_, report) = client.execute(&self.elf, &self.stdin).run().unwrap();
        let prover_gas = report.gas.unwrap_or(0);

        // Setup the proving key and verification key.
        let (pk, _vk) = client.setup(&self.elf);

        // Start timing.
        let start = std::time::Instant::now();

        // Generate the proof.
        let _ = client.prove(&pk, &self.stdin).compressed().run().unwrap();

        // Calculate duration and throughput.
        let duration = start.elapsed();
        let throughput = prover_gas as f64 / duration.as_secs_f64();

        // Return the metrics.
        CalibratorMetrics { throughput, bid_amount: 1 }
    }
}

#[cfg(test)]
mod tests {

    use sp1_sdk::include_elf;

    use super::*;

    const SPN_FIBONACCI_ELF: &[u8] = include_elf!("spn-fibonacci-program");

    #[test]
    fn test_calibrate() {
        // Create the ELF.
        let elf = SPN_FIBONACCI_ELF.to_vec();

        // Create the input stream.
        let n: u32 = 20;
        let mut stdin = SP1Stdin::new();
        stdin.write(&n);

        // Create the calibrator.
        let calibrator = SinglePassCalibrator::new(elf, stdin);

        // Calibrate the prover.
        let metrics = calibrator.calibrate();
        println!("metrics: {metrics:?}");
    }
}
