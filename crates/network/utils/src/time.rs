use std::time::{SystemTime, UNIX_EPOCH};

/// Returns the current Unix timestamp.
///
/// # Panics
///
/// Panics if the system time is before the Unix epoch (January 1, 1970).
#[must_use]
pub fn time_now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).expect("time went backwards").as_secs()
}
