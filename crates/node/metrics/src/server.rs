use crate::{hooks::Hooks, recorder::get_or_init_prometheus, version::VersionInfo};
use axum::{extract::State, response::IntoResponse, routing::get, Router};
use eyre::WrapErr;
use metrics_process::Collector;
use std::net::SocketAddr;
use tokio::{
    spawn,
    sync::{
        broadcast,
        oneshot::{self, Sender},
    },
};
use tracing::{debug, error, info, warn};

#[cfg(target_os = "linux")]
use metrics::Unit;

/// Configuration for the [`MetricServer`].
#[derive(Debug)]
pub struct MetricServerConfig {
    listen_addr: SocketAddr,
    version_info: VersionInfo,
    hooks: Hooks,
    service_name: String,
    ready_signal: Option<Sender<()>>,
}

impl Clone for MetricServerConfig {
    fn clone(&self) -> Self {
        Self {
            listen_addr: self.listen_addr,
            version_info: self.version_info.clone(),
            hooks: self.hooks.clone(),
            service_name: self.service_name.clone(),
            ready_signal: None,
        }
    }
}

/// The metrics server must be initialized and running BEFORE any metrics are recorded.
/// This ensures proper registration with the Prometheus recorder.
///
/// Example usage:
/// ```ignore
/// // 1. Create and spawn metrics server first
/// let (ready_tx, ready_rx) = oneshot::channel();
/// let (shutdown_tx, shutdown_rx) = broadcast::channel(1);
/// let config = MetricServerConfig::new(addr, version_info, "my-service".to_string())
///     .with_ready_signal(ready_tx);
/// let server = MetricServer::new(config);
/// let handle = tokio::spawn(async move { server.serve(shutdown_rx).await });
///
/// // 2. Wait for server to be ready
/// ready_rx.await?;
///
/// // 3. Only then initialize your application metrics
/// let metrics = MyMetrics::default();
/// MyMetrics::describe();
///
/// // 4. Now safe to use metrics in your application
/// metrics.my_counter.inc();
/// ```
impl MetricServerConfig {
    /// Create a new [`MetricServerConfig`] with the given configuration.
    pub fn new(listen_addr: SocketAddr, version_info: VersionInfo, service_name: String) -> Self {
        let hooks = Hooks::new();
        Self { listen_addr, hooks, version_info, service_name, ready_signal: None }
    }

    /// Set a ready signal channel that will be triggered when the server is ready.
    pub fn with_ready_signal(mut self, ready_signal: Sender<()>) -> Self {
        self.ready_signal = Some(ready_signal);
        self
    }
}

/// [`MetricServer`] responsible for serving the metrics endpoint.
#[derive(Debug, Clone)]
pub struct MetricServer {
    config: MetricServerConfig,
}

impl MetricServer {
    /// Create a new [`MetricServer`] with the given configuration
    pub const fn new(config: MetricServerConfig) -> Self {
        Self { config }
    }

    /// Spawns the metrics server with an external shutdown signal.
    ///
    /// This version of serve takes a broadcast receiver that can be used to trigger
    /// shutdown from the outside, avoiding race conditions with signal handlers.
    pub async fn serve(self, mut shutdown_signal: broadcast::Receiver<()>) -> eyre::Result<()> {
        let (internal_shutdown_tx, internal_shutdown_rx) = oneshot::channel();

        // Start the endpoint before moving out ready_signal.
        let server_handle = self
            .start_endpoint(internal_shutdown_rx)
            .await
            .wrap_err("could not start prometheus endpoint")?;

        // Now we can safely move out ready_signal.
        if let Some(ready_signal) = self.config.ready_signal {
            if ready_signal.send(()).is_err() {
                warn!("failed to send ready signal");
            } else {
                debug!("metrics server ready signal sent");
            }
        }

        // Describe metrics after recorder installation.
        Collector::default().describe();
        self.config.version_info.register_version_metrics();
        describe_io_stats();

        // Listen for the external shutdown signal
        tokio::spawn(async move {
            if shutdown_signal.recv().await.is_ok() {
                info!("received external shutdown signal, initiating graceful shutdown...");
                if internal_shutdown_tx.send(()).is_err() {
                    warn!("failed to send shutdown signal to metrics server");
                }
            }
        });

        // Wait for the server to complete.
        server_handle.await?;
        info!("metrics server shut down gracefully");

        Ok(())
    }

    async fn start_endpoint(
        &self,
        shutdown_rx: oneshot::Receiver<()>,
    ) -> eyre::Result<tokio::task::JoinHandle<()>> {
        // Initialize the prometheus recorder.
        get_or_init_prometheus(&self.config.service_name);

        let app = Router::new()
            .route("/", get(Self::metrics_handler))
            .route("/metrics", get(Self::metrics_handler))
            .with_state(self.clone());

        let listen_addr = self.config.listen_addr;
        info!("metrics server listening on {}", listen_addr);

        // Spawn a task to accept connections.
        Ok(spawn(async move {
            // Use axum's built-in server functionality with simplified shutdown
            if let Err(err) =
                axum::serve(tokio::net::TcpListener::bind(listen_addr).await.unwrap(), app)
                    .with_graceful_shutdown(async {
                        let _ = shutdown_rx.await;
                        info!("shutdown signal received for metrics server");
                    })
                    .await
            {
                error!(%err, "metrics server error");
            }
        }))
    }

    /// Handler for the metrics endpoint.
    async fn metrics_handler(State(server): State<Self>) -> impl IntoResponse {
        // Execute all hooks
        server.config.hooks.iter().for_each(|hook| hook());

        // Get metrics from prometheus
        let handle = get_or_init_prometheus(&server.config.service_name);
        handle.render()
    }
}

#[cfg(target_os = "linux")]
fn describe_io_stats() {
    use metrics::describe_counter;

    describe_counter!("io.rchar", "Characters read");
    describe_counter!("io.wchar", "Characters written");
    describe_counter!("io.syscr", "Read syscalls");
    describe_counter!("io.syscw", "Write syscalls");
    describe_counter!("io.read_bytes", Unit::Bytes, "Bytes read");
    describe_counter!("io.write_bytes", Unit::Bytes, "Bytes written");
    describe_counter!("io.cancelled_write_bytes", Unit::Bytes, "Cancelled write bytes");
}

#[cfg(not(target_os = "linux"))]
const fn describe_io_stats() {}

#[cfg(test)]
mod tests {
    use super::*;
    use reqwest::Client;
    use socket2::{Domain, Socket, Type};
    use std::net::{SocketAddr, TcpListener};

    fn get_random_available_addr() -> SocketAddr {
        let addr = &"127.0.0.1:0".parse::<SocketAddr>().unwrap().into();
        let socket = Socket::new(Domain::IPV4, Type::STREAM, None).unwrap();
        socket.set_reuse_address(true).unwrap();
        socket.bind(addr).unwrap();
        socket.listen(1).unwrap();
        let listener = TcpListener::from(socket);
        listener.local_addr().unwrap()
    }

    #[tokio::test]
    async fn test_metrics_endpoint() {
        let version_info = VersionInfo {
            version: "test".to_string(),
            build_timestamp: "test".to_string(),
            cargo_features: "test".to_string(),
            git_sha: "test".to_string(),
            target_triple: "test".to_string(),
            build_profile: "test".to_string(),
        };

        let listen_addr = get_random_available_addr();
        let config = MetricServerConfig::new(listen_addr, version_info, "test".to_string());

        // Create a shutdown channel for the server
        let (_shutdown_tx, shutdown_rx) = broadcast::channel(1);

        // Start server in separate task
        let server = MetricServer::new(config);
        let server_handle = tokio::spawn(async move { server.serve(shutdown_rx).await });

        // Give the server a moment to start
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;

        // Send request to the metrics endpoint
        let url = format!("http://{listen_addr}");
        let response = Client::new().get(&url).send().await.unwrap();
        assert!(response.status().is_success());

        // Check the response body
        let body = response.text().await.unwrap();
        assert!(!body.is_empty(), "response body should not be empty");

        // Cleanup: abort the server task
        server_handle.abort();
    }
}
