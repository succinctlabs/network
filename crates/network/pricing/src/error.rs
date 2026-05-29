use thiserror::Error;

#[derive(Debug, Error)]
pub enum PriceError {
    #[error("PROVE/USD reported as zero, refusing to divide")]
    ZeroProvePrice,
    #[error("integer overflow in price conversion")]
    Overflow,
    #[error("could not parse PROVE/USD value: {0}")]
    PriceConversion(String),
}
