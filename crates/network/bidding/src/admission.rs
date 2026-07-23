//! Gas-aware admission: conservative schedulability against the request's effective
//! deadline, plus a controller-slot capacity cap.

/// The cluster's capacity and current in-flight load. Set up once per bid pass; the
/// load fields (`active_proofs`, `active_wraps`, `committed_gas`) accumulate as
/// requests are admitted within the pass.
pub struct ClusterState {
    // Capacity.
    /// Total cluster throughput in million gas per second.
    pub throughput_mgas: f64,
    /// Per-node CPU-worker capacities in task-weight units (GB of RAM), the same
    /// measure workers declare to the coordinator. A wrap stage must fit within a
    /// single node, so per-node granularity is what bounds concurrent wraps.
    pub cpu_worker_max_weights: Vec<u32>,
    // In-flight load.
    /// Proofs currently in flight.
    pub active_proofs: u32,
    /// In-flight proofs whose mode requires a wrap stage (Groth16/Plonk).
    pub active_wraps: u32,
    /// Sum of expected gas of in-flight proofs (gas units).
    pub committed_gas: u64,
}

impl ClusterState {
    /// Concurrent proofs the fleet can hold: each active proof keeps a weight-1
    /// controller task resident on a CPU worker for its whole lifetime, so total
    /// CPU-worker weight bounds proof count.
    fn controller_slots(&self) -> u32 {
        self.cpu_worker_max_weights.iter().fold(0u32, |acc, w| acc.saturating_add(*w))
    }

    /// No controller slot free for another proof.
    fn at_capacity(&self) -> bool {
        self.active_proofs >= self.controller_slots()
    }

    /// Seconds to prove `gas` at the cluster's throughput.
    fn drain_secs(&self, gas: u64) -> f64 {
        (gas as f64 / 1_000_000.0) / self.throughput_mgas
    }

    /// Wraps the fleet can run concurrently at `wrap_weight`. A wrap must fit
    /// within one node, so slots are summed per node rather than derived from the
    /// fleet total. At least 1, so an oversized wrap serializes instead of
    /// dividing by zero.
    fn wrap_slots(&self, wrap_weight: u32) -> u32 {
        self.cpu_worker_max_weights
            .iter()
            .map(|node_weight| node_weight / wrap_weight)
            .sum::<u32>()
            .max(1)
    }

    /// Seconds the request queues behind in-flight wraps: full cycles of waiting
    /// at the fleet's slot capacity. Zero for modes without a wrap stage.
    fn wrap_queue_secs(&self, req: &RequestDemand) -> f64 {
        if req.wrap_weight == 0 {
            return 0.0;
        }
        (self.active_wraps / self.wrap_slots(req.wrap_weight)) as f64 * req.wrap_secs
    }
}

/// One request's demand on the cluster.
pub struct RequestDemand {
    /// Expected gas of the request (gas units).
    pub expected_gas: u64,
    /// Seconds until the request's effective deadline.
    pub deadline_secs: u64,
    /// Base safety buffer in seconds, excluding the wrap stage.
    pub buffer_secs: f64,
    /// Duration of this request's wrap stage in seconds; 0 for modes without one.
    /// Counted once for the request's own wrap and once per queued cycle behind
    /// in-flight wraps.
    pub wrap_secs: f64,
    /// Task weight of this request's wrap stage (GB of RAM); 0 for modes without
    /// one. Each CPU node runs `node_weight / wrap_weight` wraps per cycle, and this
    /// request queues behind the in-flight wraps at the fleet's combined rate.
    pub wrap_weight: u32,
}

impl RequestDemand {
    /// Fixed cost on top of proving time: the base buffer plus the request's own
    /// wrap stage.
    fn overhead_secs(&self) -> f64 {
        self.buffer_secs + self.wrap_secs
    }

    /// Whether an estimated completion time meets the request's deadline.
    fn fits(&self, completion_secs: f64) -> bool {
        completion_secs <= self.deadline_secs as f64
    }
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum AdmissionOutcome {
    /// Fits under conservative load (serial drain of committed gas).
    AdmitLoaded,
    /// No controller slot free — active proofs already occupy the fleet's
    /// CPU-worker weight.
    RejectCap,
    /// Can't fit the deadline even with the whole cluster — never bid.
    RejectInfeasible,
    /// Fails the loaded check — completing behind the committed queue would miss the
    /// deadline.
    RejectLoad,
}

impl AdmissionOutcome {
    pub fn admits(self) -> bool {
        matches!(self, Self::AdmitLoaded)
    }
}

/// Gas-aware admission policy.
///
/// - Reject when no controller slot is free (proof count is bounded by CPU-worker weight).
/// - Reject requests that can't fit their deadline even on an empty cluster (bidding on those means
///   a deadline miss).
/// - Admit only when the request fits under the conservative loaded model: all committed gas drains
///   serially first, and a wrap-mode request queues behind the in-flight wraps at the rate its
///   weight allows. Bidding on work that fails this check would risk missing the network's
///   performance deadline and a resulting suspension.
pub fn admission_outcome(cluster: &ClusterState, req: &RequestDemand) -> AdmissionOutcome {
    if cluster.at_capacity() {
        return AdmissionOutcome::RejectCap;
    }
    let solo = cluster.drain_secs(req.expected_gas) + req.overhead_secs();
    if !req.fits(solo) {
        return AdmissionOutcome::RejectInfeasible;
    }
    let loaded = cluster.drain_secs(cluster.committed_gas.saturating_add(req.expected_gas))
        + req.overhead_secs()
        + cluster.wrap_queue_secs(req);
    if req.fits(loaded) {
        AdmissionOutcome::AdmitLoaded
    } else {
        AdmissionOutcome::RejectLoad
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Baseline: 100 Mgas/s cluster, one 96-weight CPU node, empty load. Each test
    /// overrides the dimension under test.
    fn cluster() -> ClusterState {
        ClusterState {
            throughput_mgas: 100.0,
            cpu_worker_max_weights: vec![96],
            active_proofs: 0,
            active_wraps: 0,
            committed_gas: 0,
        }
    }

    /// Baseline request: 1 Bgas (→ 10s solo at 100 Mgas/s), roomy deadline, 30s buffer.
    fn request() -> RequestDemand {
        RequestDemand {
            expected_gas: 1_000_000_000,
            deadline_secs: 100,
            buffer_secs: 30.0,
            wrap_secs: 0.0,
            wrap_weight: 0,
        }
    }

    /// Empty cluster, fits deadline → admit (loaded tier).
    #[test]
    fn admits_when_loaded_fits() {
        assert_eq!(admission_outcome(&cluster(), &request()), AdmissionOutcome::AdmitLoaded);
    }

    /// Controller capacity (Σ CPU-worker weights) still rejects regardless of gas
    /// math: 96 active proofs fill the 96-weight node.
    #[test]
    fn rejects_at_cap() {
        let c = ClusterState { active_proofs: 96, ..cluster() };
        assert_eq!(admission_outcome(&c, &request()), AdmissionOutcome::RejectCap);
    }

    /// Controller slots sum across nodes: two 96-weight nodes hold 192 proofs, so
    /// 100 active still admits and 192 rejects.
    #[test]
    fn cap_sums_across_nodes() {
        let c =
            ClusterState { active_proofs: 100, cpu_worker_max_weights: vec![96, 96], ..cluster() };
        assert_eq!(admission_outcome(&c, &request()), AdmissionOutcome::AdmitLoaded);
        let c =
            ClusterState { active_proofs: 192, cpu_worker_max_weights: vec![96, 96], ..cluster() };
        assert_eq!(admission_outcome(&c, &request()), AdmissionOutcome::RejectCap);
    }

    /// Solo time (10s + 30s buffer) over a 35s deadline → infeasible, never bid.
    #[test]
    fn rejects_solo_infeasible() {
        let r = RequestDemand { deadline_secs: 35, ..request() };
        assert_eq!(admission_outcome(&cluster(), &r), AdmissionOutcome::RejectInfeasible);
    }

    /// Wrap queueing binds before gas throughput for heavy wrap modes: a 60-weight
    /// wrap runs alone on a 96-weight fleet, so each in-flight wrap adds one wrap
    /// cycle to the completion time.
    #[test]
    fn wrap_queue_limits_wrap_modes() {
        // 10s gas + 60s buffer + 80s own wrap + n × 80s queue ≤ 420s holds through
        // n = 3, so the fourth concurrent wrap is the last admitted.
        let r = RequestDemand {
            deadline_secs: 420,
            buffer_secs: 60.0,
            wrap_secs: 80.0,
            wrap_weight: 60,
            ..request()
        };
        let c = ClusterState { active_wraps: 3, ..cluster() };
        assert_eq!(admission_outcome(&c, &r), AdmissionOutcome::AdmitLoaded);
        let c = ClusterState { active_wraps: 4, ..cluster() };
        assert_eq!(admission_outcome(&c, &r), AdmissionOutcome::RejectLoad);
        // Modes without a wrap stage are unaffected by in-flight wraps.
        let c = ClusterState { active_wraps: 4, ..cluster() };
        assert_eq!(admission_outcome(&c, &request()), AdmissionOutcome::AdmitLoaded);
    }

    /// Lighter wraps pack more per cycle and more CPU-worker weight drains the queue
    /// faster; a wrap heavier than the fleet still gets one slot rather than
    /// dividing by zero.
    #[test]
    fn wrap_capacity_scales_with_weight() {
        // A 14-weight wrap packs 96 / 14 = 6 per cycle: 4 in-flight wraps queue for
        // zero cycles, so the request fits where a 60-weight wrap would not.
        let light = RequestDemand {
            deadline_secs: 420,
            buffer_secs: 60.0,
            wrap_secs: 80.0,
            wrap_weight: 14,
            ..request()
        };
        let c = ClusterState { active_wraps: 4, ..cluster() };
        assert_eq!(admission_outcome(&c, &light), AdmissionOutcome::AdmitLoaded);
        // A second node adds a second slot for a heavy wrap: floor(4 / 2) = 2
        // cycles fits the same budget.
        let heavy = RequestDemand { wrap_weight: 60, ..light };
        let c = ClusterState { active_wraps: 4, cpu_worker_max_weights: vec![96, 96], ..cluster() };
        assert_eq!(admission_outcome(&c, &heavy), AdmissionOutcome::AdmitLoaded);
        // Slots are per node, not fleet-total: two 96-weight nodes hold two 60-weight
        // wraps (4 queue cycles at 8 in flight), while one 192-weight node holds
        // three (2 cycles).
        let c = ClusterState { active_wraps: 8, cpu_worker_max_weights: vec![96, 96], ..cluster() };
        assert_eq!(admission_outcome(&c, &heavy), AdmissionOutcome::RejectLoad);
        let c = ClusterState { active_wraps: 8, cpu_worker_max_weights: vec![192], ..cluster() };
        assert_eq!(admission_outcome(&c, &heavy), AdmissionOutcome::AdmitLoaded);
        // A wrap heavier than the whole fleet serializes fully.
        let oversized = RequestDemand { wrap_weight: 200, ..light };
        let c = ClusterState { active_wraps: 4, ..cluster() };
        assert_eq!(admission_outcome(&c, &oversized), AdmissionOutcome::RejectLoad);
    }

    /// Committed load pushes completion past the deadline, though the request is
    /// solo-feasible → reject.
    #[test]
    fn rejects_on_load() {
        // loaded = (9 + 1) Bgas / 100 Mgas/s + 30 = 130s > 100s; solo = 40s ≤ 100s.
        let c = ClusterState { committed_gas: 9_000_000_000, ..cluster() };
        assert_eq!(admission_outcome(&c, &request()), AdmissionOutcome::RejectLoad);
    }
}
