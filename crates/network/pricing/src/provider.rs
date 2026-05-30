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

impl ProvePrice {
    /// Parse a PROVE/USD reading from the wire fields of a `GetProvePriceResponse`.
    pub fn parse(price_str: &str, last_updated_unix: i64) -> Result<Self, PriceError> {
        let usd_micros = crate::math::parse_usd_micros(price_str)?;
        let as_of = OffsetDateTime::from_unix_timestamp(last_updated_unix)
            .map_err(|_| PriceError::InvalidTimestamp(last_updated_unix))?;
        Ok(Self { usd_micros, as_of })
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_typical() {
        let p = ProvePrice::parse("0.40", 1_700_000_000).unwrap();
        assert_eq!(p.usd_micros, 400_000);
        assert_eq!(p.as_of.unix_timestamp(), 1_700_000_000);
    }

    #[test]
    fn parse_rejects_bad_price() {
        assert!(matches!(
            ProvePrice::parse("0", 1_700_000_000),
            Err(PriceError::PriceConversion(_))
        ));
    }

    #[test]
    fn parse_rejects_invalid_timestamp() {
        // OffsetDateTime::from_unix_timestamp rejects values outside its supported range.
        assert!(matches!(
            ProvePrice::parse("0.40", i64::MAX),
            Err(PriceError::InvalidTimestamp(_))
        ));
    }
}
