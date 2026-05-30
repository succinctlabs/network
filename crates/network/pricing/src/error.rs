use thiserror::Error;

#[derive(Debug, Error)]
pub enum PriceError {
    #[error("no PROVE/USD price available (no live read, no last-known cache)")]
    NoPriceAvailable,
    #[error("PROVE/USD reported as zero, refusing to divide")]
    ZeroProvePrice,
    #[error("integer overflow in price conversion")]
    Overflow,
    #[error("could not parse PROVE/USD value: {0}")]
    PriceConversion(String),
    #[error("invalid last_updated unix timestamp: {0}")]
    InvalidTimestamp(i64),
    /// Catch-all for implementation-specific failures (DB drivers, RPC clients, etc.).
    #[error("price provider failed: {0}")]
    Provider(String),
}
