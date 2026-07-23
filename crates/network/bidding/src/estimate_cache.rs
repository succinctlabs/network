//! Client-side TTL cache for published program gas estimates.
//!
//! Entries cache the *resolution*: a program the network reports no history for caches
//! as absent, so unknown programs are not re-fetched every bid pass. Callers pass
//! `now` explicitly, keeping the type pure and its TTL behavior directly testable.

use std::{
    collections::HashMap,
    time::{Duration, Instant},
};

/// How long a cached resolution serves before the network is consulted again. The
/// published estimate changes slowly relative to the bid loop, so a long interval
/// loses no useful freshness while sparing the network repeated lookups. Deliberately
/// a constant, not a knob.
pub const ESTIMATE_TTL: Duration = Duration::from_secs(300);

/// Upper bound on cached programs.
const MAX_ENTRIES: usize = 4096;

struct Entry {
    /// `Some` = published estimate; `None` = known absent (no fulfilled history).
    estimate: Option<u64>,
    fetched_at: Instant,
}

/// Result of a cache lookup: three states, because "never asked" and "asked, the
/// network reported no history" must stay distinguishable — collapsing them would
/// refetch known-absent programs on every pass.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EstimateLookup {
    /// No fresh entry — ask the network.
    Miss,
    /// Fresh entry: the network reported no fulfilled history for this program.
    KnownAbsent,
    /// Fresh entry with a published estimate.
    Hit(u64),
}

/// TTL map `vk_hash → resolution`, bounded by [`MAX_ENTRIES`].
#[derive(Default)]
pub struct EstimateCache {
    entries: HashMap<Vec<u8>, Entry>,
}

impl EstimateCache {
    pub fn new() -> Self {
        Self::default()
    }

    /// Fresh resolution for `vk_hash`; see [`EstimateLookup`] for the three states.
    pub fn lookup(&self, vk_hash: &[u8], now: Instant) -> EstimateLookup {
        match self.entries.get(vk_hash) {
            Some(entry) if now.duration_since(entry.fetched_at) < ESTIMATE_TTL => {
                match entry.estimate {
                    Some(estimate) => EstimateLookup::Hit(estimate),
                    None => EstimateLookup::KnownAbsent,
                }
            }
            _ => EstimateLookup::Miss,
        }
    }

    /// Store a freshly fetched resolution. Expired entries are evicted when at
    /// capacity; anything that still doesn't fit is not cached (the cache is an
    /// optimization, never a gate).
    pub fn store(&mut self, vk_hash: Vec<u8>, estimate: Option<u64>, now: Instant) {
        if self.entries.len() >= MAX_ENTRIES && !self.entries.contains_key(&vk_hash) {
            self.entries.retain(|_, e| now.duration_since(e.fetched_at) < ESTIMATE_TTL);
            if self.entries.len() >= MAX_ENTRIES {
                return;
            }
        }
        self.entries.insert(vk_hash, Entry { estimate, fetched_at: now });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Fresh entries serve; expired entries read as uncached.
    #[test]
    fn ttl_expiry() {
        let mut cache = EstimateCache::new();
        let t0 = Instant::now();
        cache.store(vec![1], Some(100), t0);
        assert_eq!(cache.lookup(&[1], t0), EstimateLookup::Hit(100));
        assert_eq!(cache.lookup(&[1], t0 + ESTIMATE_TTL), EstimateLookup::Miss);
    }

    /// Known-absent programs cache as a resolved absence, avoiding a refetch.
    #[test]
    fn negative_caching() {
        let mut cache = EstimateCache::new();
        let t0 = Instant::now();
        cache.store(vec![2], None, t0);
        assert_eq!(cache.lookup(&[2], t0), EstimateLookup::KnownAbsent);
    }

    /// At capacity with all entries fresh, new vks are simply not cached.
    #[test]
    fn full_cache_never_gates() {
        let mut cache = EstimateCache::new();
        let t0 = Instant::now();
        for i in 0..MAX_ENTRIES as u16 {
            cache.store(i.to_be_bytes().to_vec(), Some(1), t0);
        }
        cache.store(vec![0xFF; 3], Some(2), t0);
        assert_eq!(
            cache.lookup(&[0xFF; 3], t0),
            EstimateLookup::Miss,
            "not cached, caller still serves it"
        );
        // Once the old entries expire, new vks cache again.
        let later = t0 + ESTIMATE_TTL;
        cache.store(vec![0xFF; 3], Some(2), later);
        assert_eq!(cache.lookup(&[0xFF; 3], later), EstimateLookup::Hit(2));
    }
}
