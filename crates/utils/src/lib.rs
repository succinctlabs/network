mod cuda;
mod domain;
mod error;
mod logger;
mod time;

pub use cuda::*;
pub use domain::*;
pub use error::*;
pub use logger::*;
pub use time::*;

use std::sync::LazyLock;

use alloy_primitives::B256;
use alloy_sol_types::eip712_domain;
use anyhow::{anyhow, Result};

/// The [Eip712Domain] separator for the vApp on Sepolia.
pub static SPN_SEPOLIA_V1_DOMAIN: LazyLock<B256> = LazyLock::new(|| {
    let domain = eip712_domain! {
        name: "Succinct Prover Network",
        version: "1.0.0",
        chain_id: 11155111,
    };
    domain.separator()
});

/// The [Eip712Domain] separator for the vApp on Sepolia.
pub static SPN_MAINNET_V1_DOMAIN: LazyLock<B256> = LazyLock::new(|| {
    let domain = eip712_domain! {
        name: "Succinct Prover Network",
        version: "1.0.0",
        chain_id: 1,
    };
    domain.separator()
});

/// Returns the domain separator for the given domain name.
pub fn get_domain(name: &str) -> Result<B256> {
    match name {
        "SPN_MAINNET_V1_DOMAIN" => Ok(*SPN_MAINNET_V1_DOMAIN),
        "SPN_SEPOLIA_V1_DOMAIN" => Ok(*SPN_SEPOLIA_V1_DOMAIN),
        _ => Err(anyhow!("Invalid domain name: {}", name)),
    }
}
