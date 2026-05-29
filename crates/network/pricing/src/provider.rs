use async_trait::async_trait;
use time::OffsetDateTime;

use crate::error::PriceError;

/// A PROVE/USD reading and the time it applies to.
#[derive(Clone, Debug)]
pub struct ProvePrice {
    /// µUSD per 1 PROVE.
    pub usd_micros: u64,
    /// When this price reading applies. Callers compute staleness themselves as
    /// `OffsetDateTime::now_utc() - as_of` so cached values reflect *current* age,
    /// not the age at fetch time.
    pub as_of: OffsetDateTime,
}

/// Source of a PROVE/USD reading.
///
/// Implementations may back this with any source (DB row, RPC call, in-memory cache, mock).
/// Implementation-specific failures (DB driver errors, RPC errors, etc.) flow through
/// [`PriceError::Provider`] via `.to_string()`.
///
/// Implementations should attempt a live read first and fall back to the last-known value
/// on transient failure. Only return `Err` when *no* value is available — not even a cached
/// one. Callers may inspect [`ProvePrice::as_of`] to apply their own staleness threshold.
#[async_trait]
pub trait PriceProvider: Send + Sync {
    /// Return the freshest available PROVE/USD reading.
    async fn current_prove_usd_micros(&self) -> Result<ProvePrice, PriceError>;
}
