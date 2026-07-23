//! Expected-gas policy: reconcile the network-published estimate with a request's own
//! limits into the single value used by admission. The estimation method is
//! server-side and not modeled here.

/// Expected gas for a request: the published estimate scaled by `estimate_multiplier`,
/// capped by the request's own budget; the budget alone when the program has no
/// published history. The `min` with the budget keeps a small per-request limit
/// authoritative even when the program's history is larger.
///
/// `estimate_multiplier` is normally 1.0; operators raise it to size estimates more
/// conservatively, or lower it when estimates consistently exceed observed usage.
/// Callers validate it finite and positive at startup.
pub fn expected_gas(
    estimate: Option<u64>,
    gas_limit: u64,
    cycle_limit: u64,
    estimate_multiplier: f64,
) -> u64 {
    // gas_limit == 0 means the cycle limit governs execution (proto contract). Fall
    // back to it so an unsized request is not treated as zero-cost and admitted
    // freely; cycle count is close to gas in magnitude and serves as a budget.
    let limit = if gas_limit > 0 { gas_limit } else { cycle_limit };
    // A non-positive estimate carries no information; treat it as absent rather than
    // letting the request through admission at zero cost.
    let estimate = estimate.filter(|&e| e > 0);
    match estimate {
        Some(e) => ((e as f64 * estimate_multiplier) as u64).min(limit),
        None => limit,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// No estimate → the request's own budget; gas_limit=0 → cycle_limit governs.
    /// The multiplier never applies to the limit fallback.
    #[test]
    fn no_estimate_falls_back_to_limits() {
        assert_eq!(expected_gas(None, 5_000, 9_000, 2.0), 5_000);
        assert_eq!(expected_gas(None, 0, 9_000, 2.0), 9_000);
    }

    /// A published estimate of 0 is treated as absent, not as a free request.
    #[test]
    fn zero_estimate_treated_as_absent() {
        assert_eq!(expected_gas(Some(0), 5_000, 0, 1.0), 5_000);
    }

    /// Estimates are capped by an honest per-request budget but never inflated by it.
    #[test]
    fn min_with_limit() {
        assert_eq!(expected_gas(Some(10_000), 5_000, 0, 1.0), 5_000);
        assert_eq!(expected_gas(Some(3_000), 5_000, 0, 1.0), 3_000);
        assert_eq!(expected_gas(Some(3_000), 0, 2_000, 1.0), 2_000);
    }

    /// The multiplier scales the estimate before the budget cap, in both directions.
    #[test]
    fn multiplier_scales_estimate() {
        assert_eq!(expected_gas(Some(3_000), 100_000, 0, 1.5), 4_500);
        assert_eq!(expected_gas(Some(3_000), 100_000, 0, 0.5), 1_500);
        assert_eq!(expected_gas(Some(3_000), 4_000, 0, 2.0), 4_000, "cap still wins");
    }
}
