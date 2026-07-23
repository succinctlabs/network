//! The network's published prover performance requirements, as bidding inputs.
//!
//! A fulfilled request counts toward the prover's success rate only if fulfilled
//! within `perf_deadline` of its creation; falling below the success-rate bar leads
//! to suspension. Proto-free: each bidder adapts its generated response type via
//! [`PerformanceRequirements::from_parts`].

/// The performance budget parameters: `budget = max(floor, gas / rate)`.
#[derive(Debug, Clone, PartialEq)]
pub struct PerformanceRequirements {
    /// Whole-request proving rate in MGas/s required whenever it grants more time
    /// than the floor.
    pub min_mgas_per_second: f64,
    /// Minimum time budget in seconds granted to every request.
    pub floor_latency_seconds: u64,
}

impl PerformanceRequirements {
    /// Build from wire primitives. Returns `None` when the rate doesn't parse to a
    /// finite positive number — degrading to unclamped bidding, same as when the
    /// network publishes no requirements at all.
    pub fn from_parts(min_mgas_per_second: &str, floor_latency_seconds: u64) -> Option<Self> {
        let min_mgas_per_second: f64 = min_mgas_per_second.parse().ok()?;
        if !min_mgas_per_second.is_finite() || min_mgas_per_second <= 0.0 {
            return None;
        }
        Some(Self { min_mgas_per_second, floor_latency_seconds })
    }
}

/// Absolute unix deadline by which a request of `expected_gas` must be fulfilled to
/// count as successful under the network's performance requirements: the budget is
/// `max(floor, gas / rate)`.
///
/// The network judges on actual `gas_used`, which is unknown before execution;
/// `expected_gas` is an estimate. When the rate term governs, an overestimate yields a
/// looser budget than the network will apply. This is tolerated: admission sizes
/// completion time from the same `expected_gas`, so both estimates move together, and
/// the rate term binds only when the effective pace falls below the published rate.
pub fn perf_deadline(created_at: u64, expected_gas: u64, req: &PerformanceRequirements) -> u64 {
    let rate_secs = (expected_gas as f64 / (req.min_mgas_per_second * 1e6)) as u64;
    created_at.saturating_add(rate_secs.max(req.floor_latency_seconds))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn requirements() -> PerformanceRequirements {
        PerformanceRequirements { min_mgas_per_second: 24.0, floor_latency_seconds: 420 }
    }

    #[test]
    fn parses_valid_parts() {
        assert_eq!(PerformanceRequirements::from_parts("24", 420), Some(requirements()));
    }

    #[test]
    fn invalid_rate_parses_to_none() {
        for rate in ["", "abc", "0", "-24", "NaN", "inf"] {
            assert_eq!(PerformanceRequirements::from_parts(rate, 420), None, "rate {rate}");
        }
    }

    /// The rate would grant 0s and ~42s respectively; the 420s floor governs.
    #[test]
    fn small_gas_gets_floor_budget() {
        assert_eq!(perf_deadline(1_000, 0, &requirements()), 1_420);
        assert_eq!(perf_deadline(1_000, 1_000_000_000, &requirements()), 1_420);
    }

    /// 14.4B gas / 24 MGas/s = 600s, above the 420s floor.
    #[test]
    fn large_gas_gets_rate_budget() {
        assert_eq!(perf_deadline(1_000, 14_400_000_000, &requirements()), 1_000 + 600);
    }

    #[test]
    fn saturates_instead_of_overflowing() {
        assert_eq!(perf_deadline(u64::MAX, u64::MAX, &requirements()), u64::MAX);
    }
}
