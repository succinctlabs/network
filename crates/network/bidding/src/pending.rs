//! Ledger of own bids awaiting assignment.
//!
//! The auction settles well after the bid pass cadence, so without this ledger a
//! burst is re-admitted every pass until assignments land: committed load must
//! include what the bidder just promised. Callers pass `now` explicitly, keeping
//! the type pure and its expiry behavior testable.

use std::{
    collections::HashMap,
    time::{Duration, Instant},
};

use crate::admission::ClusterState;

/// Settlement slack past a request's `min_auction_period` (auctioneer tick,
/// assignment write, our next poll). A lost auction's entry expires at
/// `bid_at + min_auction_period + slack` — one auction cycle, no longer.
const PENDING_BID_SETTLE_SLACK: Duration = Duration::from_secs(15);

/// Ceiling on any entry's lifetime, whatever the request's auction period claims.
pub const PENDING_BID_TTL: Duration = Duration::from_secs(60);

/// A bid placed but not yet visible as assigned.
struct PendingBid {
    expected_gas: u64,
    is_wrap: bool,
    expires_at: Instant,
}

/// TTL ledger `request_id -> promised load`.
#[derive(Default)]
pub struct PendingBids {
    entries: HashMap<Vec<u8>, PendingBid>,
}

impl PendingBids {
    /// Record a bid about to be submitted. `min_auction_period_secs` is the
    /// request's auction floor: settlement cannot happen before it, so the entry
    /// expires a settle-slack after it, capped by [`PENDING_BID_TTL`].
    pub fn record(
        &mut self,
        request_id: Vec<u8>,
        expected_gas: u64,
        is_wrap: bool,
        min_auction_period_secs: u64,
        now: Instant,
    ) {
        let ttl = (Duration::from_secs(min_auction_period_secs) + PENDING_BID_SETTLE_SLACK)
            .min(PENDING_BID_TTL);
        self.entries
            .insert(request_id, PendingBid { expected_gas, is_wrap, expires_at: now + ttl });
    }

    /// Reconcile the ledger with what this pass can see, then count every entry
    /// still outstanding as committed load on `cluster`.
    ///
    /// An entry resolves — and is dropped — when its request appears in
    /// `visible_ids`: assigned means we won, and the caller already counts it;
    /// biddable again means our bid never registered. An expired entry resolves
    /// as lost. Whatever remains is a live promise the cluster must hold
    /// capacity for.
    pub fn reconcile_into<'a>(
        &mut self,
        cluster: &mut ClusterState,
        visible_ids: impl IntoIterator<Item = &'a Vec<u8>>,
        now: Instant,
    ) {
        self.entries.retain(|_, bid| now < bid.expires_at);
        for id in visible_ids {
            self.entries.remove(id);
        }
        for bid in self.entries.values() {
            cluster.active_proofs += 1;
            if bid.is_wrap {
                cluster.active_wraps += 1;
            }
            cluster.committed_gas = cluster.committed_gas.saturating_add(bid.expected_gas);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cluster() -> ClusterState {
        ClusterState {
            throughput_mgas: 100.0,
            cpu_worker_max_weights: vec![96],
            active_proofs: 0,
            active_wraps: 0,
            committed_gas: 0,
        }
    }

    /// Unresolved bids charge committed load with their wrap flag; visible entries
    /// leave the ledger.
    #[test]
    fn reconcile_drops_visible() {
        let mut pending = PendingBids::default();
        let t0 = Instant::now();
        pending.record(vec![1], 100, false, 15, t0);
        pending.record(vec![2], 200, true, 15, t0);
        pending.record(vec![3], 300, false, 15, t0);

        // Request 3 is visible again (assigned or biddable): dropped, not counted.
        let mut c = cluster();
        pending.reconcile_into(&mut c, [vec![3]].iter(), t0);
        assert_eq!(c.active_proofs, 2);
        assert_eq!(c.active_wraps, 1);
        assert_eq!(c.committed_gas, 300);
    }

    /// An entry expires one settle-slack past its auction period, and never later
    /// than the ceiling.
    #[test]
    fn per_entry_expiry_capped_by_ceiling() {
        let mut pending = PendingBids::default();
        let t0 = Instant::now();
        pending.record(vec![1], 100, false, 15, t0);
        pending.record(vec![2], 200, false, 3_600, t0);

        // 15s auction + 15s slack: gone at t0+30, the hour-long one still held.
        let mut c = cluster();
        pending.reconcile_into(&mut c, [].iter(), t0 + Duration::from_secs(30));
        assert_eq!(c.committed_gas, 200);

        // The ceiling caps the hour-long auction period.
        let mut c2 = cluster();
        pending.reconcile_into(&mut c2, [].iter(), t0 + PENDING_BID_TTL);
        assert_eq!(c2.committed_gas, 0);
    }
}
