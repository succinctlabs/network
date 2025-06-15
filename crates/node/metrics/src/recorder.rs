//! Prometheus recorder

use metrics_exporter_prometheus::{PrometheusBuilder, PrometheusHandle};
use metrics_util::layers::{PrefixLayer, Stack};
use std::sync::OnceLock;

/// Installs the Prometheus recorder as the global recorder.
pub fn get_or_init_prometheus(service_name: &str) -> &'static PrometheusHandle {
    PROMETHEUS_RECORDER_HANDLE.get_or_init(|| PrometheusRecorder::install(service_name))
}

/// The default Prometheus recorder handle. We use a global static to ensure that it is only
/// installed once.
static PROMETHEUS_RECORDER_HANDLE: OnceLock<PrometheusHandle> = OnceLock::new();

/// Prometheus recorder installer.
#[derive(Debug)]
pub struct PrometheusRecorder;

impl PrometheusRecorder {
    /// Installs Prometheus as the metrics recorder.
    pub fn install(service_name: &str) -> PrometheusHandle {
        let builder = PrometheusBuilder::new().add_global_label("service", service_name);
        let recorder = builder.build_recorder();
        let handle = recorder.handle();

        // Build metrics stack
        Stack::new(recorder)
            .push(PrefixLayer::new("spn"))
            .install()
            .expect("Couldn't set metrics recorder.");

        handle
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    // Dependencies using different version of the `metrics` crate (to be exact, 0.21 vs 0.22)
    // may not be able to communicate with each other through the global recorder.
    //
    // This test ensures that `metrics-process` dependency plays well with the current
    // `metrics-exporter-prometheus` dependency version.
    #[test]
    fn process_metrics() {
        // initialize the lazy handle
        let _ = PROMETHEUS_RECORDER_HANDLE.get_or_init(|| PrometheusRecorder::install("spn"));

        let process = metrics_process::Collector::default();
        process.describe();
        process.collect();

        let metrics =
            PROMETHEUS_RECORDER_HANDLE.get_or_init(|| PrometheusRecorder::install("spn")).render();
        assert!(metrics.contains("process_cpu_seconds_total"), "{metrics:?}");
    }
}
