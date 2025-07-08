use metrics_process::Collector;
use once_cell::sync::Lazy;
use std::{fmt, sync::Arc, time::SystemTime};

pub(crate) trait Hook: Fn() + Send + Sync {}
impl<T: Fn() + Send + Sync> Hook for T {}

impl fmt::Debug for Hooks {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let hooks_len = self.inner.len();
        f.debug_struct("Hooks")
            .field("inner", &format!("Arc<Vec<Box<dyn Hook>>>, len: {hooks_len}"))
            .finish()
    }
}

/// Helper type for managing hooks.
#[derive(Clone)]
pub struct Hooks {
    inner: Arc<Vec<Box<dyn Hook<Output = ()>>>>,
}

impl Hooks {
    /// Create a new set of hooks.
    pub fn new() -> Self {
        let collector = Collector::default();
        let hooks: Vec<Box<dyn Hook<Output = ()>>> = vec![
            Box::new(move || collector.collect()),
            Box::new(collect_memory_stats),
            Box::new(collect_io_stats),
            Box::new(collect_uptime_seconds),
        ];
        Self { inner: Arc::new(hooks) }
    }

    pub(crate) fn iter(&self) -> impl Iterator<Item = &Box<dyn Hook<Output = ()>>> {
        self.inner.iter()
    }
}

impl Default for Hooks {
    fn default() -> Self {
        Self::new()
    }
}

fn collect_memory_stats() {}

#[cfg(target_os = "linux")]
fn collect_io_stats() {
    use metrics::counter;
    use tracing::error;

    let Ok(process) = procfs::process::Process::myself()
        .map_err(|error| error!(%error, "failed to get currently running process"))
    else {
        return;
    };

    let Ok(io) = process.io().map_err(
        |error| error!(%error, "failed to get io stats for the currently running process"),
    ) else {
        return;
    };

    counter!("io.rchar").absolute(io.rchar);
    counter!("io.wchar").absolute(io.wchar);
    counter!("io.syscr").absolute(io.syscr);
    counter!("io.syscw").absolute(io.syscw);
    counter!("io.read_bytes").absolute(io.read_bytes);
    counter!("io.write_bytes").absolute(io.write_bytes);
    counter!("io.cancelled_write_bytes").absolute(io.cancelled_write_bytes);
}

#[cfg(not(target_os = "linux"))]
const fn collect_io_stats() {}

/// Global start time of the process.
static START_TIME: Lazy<SystemTime> = Lazy::new(SystemTime::now);

/// Collects and records the process uptime in seconds.
fn collect_uptime_seconds() {
    use metrics::gauge;
    let uptime = START_TIME.elapsed().unwrap_or_default().as_secs();
    let gauge = gauge!("process_uptime_seconds");
    gauge.set(uptime as f64);
}
