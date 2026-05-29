use alloy::primitives::U256;

use crate::error::PriceError;

/// Compute a `max_price_per_pgu` ceiling in PROVE wei from a USD target.
///
/// ```text
/// ceiling_wei_per_pgu = (target_usd_micros_per_bpgu * 10^9) / prove_usd_micros
/// ```
///
/// Inputs are both integers in µUSD-denominated units:
/// - `target_usd_micros_per_bpgu`: µUSD per BPGU (1 BPGU = 10^9 PGU). 200_000 = $0.20/BPGU.
/// - `prove_usd_micros`: µUSD per 1 PROVE. 400_000 = $0.40/PROVE.
///
/// Result rounds **down**, which is conservative for the consumer: the realized $-value
/// can never inadvertently exceed `target` due to rounding.
pub fn compute_max_price_per_pgu_wei(
    target_usd_micros_per_bpgu: u64,
    prove_usd_micros: u64,
) -> Result<U256, PriceError> {
    if prove_usd_micros == 0 {
        return Err(PriceError::ZeroProvePrice);
    }
    let scale = U256::from(10u64).pow(U256::from(9u64));
    let numerator =
        U256::from(target_usd_micros_per_bpgu).checked_mul(scale).ok_or(PriceError::Overflow)?;
    Ok(numerator / U256::from(prove_usd_micros))
}

/// Parse a PROVE/USD decimal string (e.g. `"0.40"`) into µUSD (`400_000`).
///
/// The price must be finite and strictly positive. A zero or negative PROVE price is
/// meaningless and would later force a divide-by-zero in [`compute_max_price_per_pgu_wei`].
/// The result is rounded to nearest µUSD and is always `>= 1`: a price so small it rounds
/// below 1 µUSD is rejected, so the returned value is strictly positive.
pub fn parse_usd_micros(s: &str) -> Result<u64, PriceError> {
    let price: f64 = s.trim().parse().map_err(|_| {
        PriceError::PriceConversion(format!("could not parse PROVE/USD {s:?} as f64"))
    })?;
    if !price.is_finite() || price <= 0.0 {
        return Err(PriceError::PriceConversion(format!(
            "PROVE/USD must be finite and positive, got {price}"
        )));
    }
    let micros = (price * 1_000_000.0).round();
    if micros < 1.0 {
        return Err(PriceError::PriceConversion(format!(
            "PROVE/USD {price} rounds below 1 µUSD; too small to represent"
        )));
    }
    if micros >= u64::MAX as f64 {
        return Err(PriceError::PriceConversion(format!(
            "PROVE/USD {price} is out of representable µUSD range"
        )));
    }
    Ok(micros as u64)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Reference anchor: $0.20/BPGU at PROVE=$0.40 → 500_000_000 wei/PGU = 0.5 PROVE/BPGU.
    #[test]
    fn reference_anchor_matches_legacy_500m() {
        let wei = compute_max_price_per_pgu_wei(200_000, 400_000).unwrap();
        assert_eq!(wei, U256::from(500_000_000u64));
    }

    /// Lower PROVE price → higher PROVE ceiling (more wei needed per BPGU).
    #[test]
    fn lower_prove_price_raises_prove_ceiling() {
        let wei = compute_max_price_per_pgu_wei(200_000, 200_000).unwrap();
        assert_eq!(wei, U256::from(1_000_000_000u64));
    }

    /// Higher PROVE price → lower PROVE ceiling.
    #[test]
    fn higher_prove_price_lowers_prove_ceiling() {
        let wei = compute_max_price_per_pgu_wei(200_000, 1_000_000).unwrap();
        assert_eq!(wei, U256::from(200_000_000u64));
    }

    #[test]
    fn zero_prove_price_errors() {
        assert!(matches!(
            compute_max_price_per_pgu_wei(200_000, 0),
            Err(PriceError::ZeroProvePrice)
        ));
    }

    /// Division rounds down.
    #[test]
    fn rounds_down() {
        // target=1, prove=3 → 1 * 10^9 / 3 = 333_333_333 (truncated).
        let wei = compute_max_price_per_pgu_wei(1, 3).unwrap();
        assert_eq!(wei, U256::from(333_333_333u64));
    }

    /// `u64::MAX * 10^9` fits in U256 (U256 maxes at ~1.16e77; this is ~1.8e28).
    #[test]
    fn very_large_target_does_not_overflow_u256() {
        let wei = compute_max_price_per_pgu_wei(u64::MAX, 1_000_000).unwrap();
        assert!(wei > U256::ZERO);
    }

    #[test]
    fn parse_usd_micros_typical() {
        assert_eq!(parse_usd_micros("0.40").unwrap(), 400_000);
        assert_eq!(parse_usd_micros("0.2337").unwrap(), 233_700);
        assert_eq!(parse_usd_micros(" 1 ").unwrap(), 1_000_000);
    }

    #[test]
    fn parse_usd_micros_rounds_to_nearest() {
        // 0.2337005 → 233_700.5 → rounds to 233_701.
        assert_eq!(parse_usd_micros("0.2337005").unwrap(), 233_701);
    }

    #[test]
    fn parse_usd_micros_rejects_non_positive_and_garbage() {
        assert!(parse_usd_micros("0").is_err());
        assert!(parse_usd_micros("-0.5").is_err());
        assert!(parse_usd_micros("inf").is_err());
        assert!(parse_usd_micros("NaN").is_err());
        assert!(parse_usd_micros("abc").is_err());
    }

    #[test]
    fn parse_usd_micros_subunit_boundary() {
        // 0.0000004 USD = 0.4 µUSD → rounds to 0, must be rejected (not Ok(0)).
        assert!(parse_usd_micros("0.0000004").is_err());
        // 0.0000005 USD = 0.5 µUSD → rounds to 1, the smallest accepted value.
        assert_eq!(parse_usd_micros("0.0000005").unwrap(), 1);
    }
}
