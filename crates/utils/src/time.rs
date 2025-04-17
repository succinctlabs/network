use std::time::{SystemTime, UNIX_EPOCH};

/// Returns the current Unix timestamp.
pub fn time_now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).expect("time went backwards").as_secs()
}
