//! Pure bidding policy shared by SPN bidders.
//!
//! Everything here is plain data and math — no proto types, no I/O — so the
//! sp1-cluster bidder and the network-services bidder consume one implementation and
//! one test suite. Each bidder keeps a thin adapter from its own generated proto
//! types to these inputs.

pub mod admission;
pub mod estimate_cache;
pub mod policy;
pub mod requirements;

pub use admission::{admission_outcome, AdmissionOutcome, ClusterState, RequestDemand};
pub use estimate_cache::{EstimateCache, EstimateLookup};
pub use policy::expected_gas;
pub use requirements::{perf_deadline, PerformanceRequirements};
