use crate::{
    hooks::{Hook, Hooks},
    recorder::get_or_init_prometheus,
    version::VersionInfo,
};
use eyre::WrapErr;
use metrics_process::Collector;
use std::{net::SocketAddr, sync::Arc};
use tokio::{
    io::AsyncWriteExt,
    select, spawn,
    sync::oneshot::{self, Sender},
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

/// The metrics server must be initialized and running BEFORE any metrics are recorded.
/// This ensures proper registration with the Prometheus recorder.
///
/// Example usage:
/// ```ignore
/// // 1. Create and spawn metrics server first
/// let (ready_tx, ready_rx) = oneshot::channel();
/// let config = MetricServerConfig::new(addr, version_info, "my-service".to_string())
///     .with_ready_signal(ready_tx);
/// let server = MetricServer::new(config);
/// let handle = tokio::spawn(async move { server.serve().await });
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
#[derive(Debug)]
pub struct MetricServer {
    config: MetricServerConfig,
}

impl MetricServer {
    /// Create a new [`MetricServer`] with the given configuration
    pub const fn new(config: MetricServerConfig) -> Self {
        Self { config }
    }

    /// Spawns the metrics server.
    pub async fn serve(self, shutdown_rx: oneshot::Receiver<()>) -> eyre::Result<()> {
        // Clone hooks before creating the closure.
        let hooks = self.config.hooks.clone();

        // Start the endpoint before moving out ready_signal.
        let server_handle = self
            .start_endpoint(
                self.config.listen_addr,
                self.config.service_name.clone(),
                Arc::new(move || hooks.iter().for_each(|hook| hook())),
                shutdown_rx,
            )
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

        // Wait for the server to complete.
        server_handle.await?;
        info!("metrics server shut down gracefully");

        Ok(())
    }

    async fn start_endpoint<F: Hook + 'static>(
        &self,
        listen_addr: SocketAddr,
        service_name: String,
        hook: Arc<F>,
        mut shutdown_rx: oneshot::Receiver<()>,
    ) -> eyre::Result<tokio::task::JoinHandle<()>> {
        let listener = tokio::net::TcpListener::bind(listen_addr)
            .await
            .wrap_err("could not bind to address")?;

        // Initialize the prometheus recorder.
        get_or_init_prometheus(&service_name);
        info!("metrics server listening on {}", listen_addr);

        // Spawn a task to accept connections.
        Ok(spawn(async move {
            loop {
                select! {
                    // Handle shutdown signal.
                    _ = &mut shutdown_rx => {
                        info!("shutdown signal received for metrics server");
                        break;
                    }
                    // Accept incoming connections.
                    accept_result = listener.accept() => {
                        match accept_result {
                            Ok((mut stream, _remote_addr)) => {
                                let hook = hook.clone();
                                let service_name = service_name.clone();

                                // Spawn a new task to handle the connection.
                                spawn(async move {
                                    (hook)();
                                    let handle = get_or_init_prometheus(&service_name);
                                    let metrics = handle.render();

                                    let response = format!(
                                        "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {}\r\n\r\n{}",
                                        metrics.len(),
                                        metrics
                                    );

                                    if let Err(err) = stream.write_all(response.as_bytes()).await {
                                        error!(%err, "failed to write response");
                                    }
                                    if let Err(err) = stream.flush().await {
                                        error!(%err, "failed to flush response");
                                    }
                                });
                            }
                            Err(err) => {
                                error!(%err, "failed to accept connection");
                                continue;
                            }
                        }
                    }
                }
            }
        }))
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

        // Start server in separate task
        let server = MetricServer::new(config);
        let (_shutdown_tx, shutdown_rx) = oneshot::channel();
        let server_handle = tokio::spawn(async move { server.serve(shutdown_rx).await });

        // Give the server a moment to start
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;

        // Send request to the metrics endpoint
        let url = format!("http://{}", listen_addr);
        let response = Client::new().get(&url).send().await.unwrap();
        assert!(response.status().is_success());

        // Check the response body
        let body = response.text().await.unwrap();
        assert!(!body.is_empty(), "response body should not be empty");

        // Cleanup: abort the server task
        server_handle.abort();
    }
}
