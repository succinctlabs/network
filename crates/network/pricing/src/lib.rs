//! PROVE/USD wire-format parsing and USD→PROVE conversion shared across SPN consumers
//! (proxy, bidders, indexers, third-party clients). These are protocol-adjacent helpers:
//! every consumer of `GetProvePrice` and every implementer of dynamic `max_price_per_pgu`
//! must agree on the parsing and unit math, so they live here as a single source of truth.

mod error;
mod math;
mod provider;

pub use error::PriceError;
pub use math::{
    compute_max_price_per_pgu_wei, parse_usd_micros, round_down_to_tick, usd_micros_to_prove_wei,
};
pub use provider::{PriceProvider, ProvePrice};
