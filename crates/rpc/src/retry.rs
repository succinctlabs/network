use anyhow::Result;
use backoff::{future::retry, Error as BackoffError, ExponentialBackoff};
use spn_network_types::prover_network_client::ProverNetworkClient;
use std::time::Duration;
use tonic::{async_trait, transport::Channel, Code};
use tracing::{error, warn};

/// Default timeout for retry operations.
pub const DEFAULT_RETRY_TIMEOUT: Duration = Duration::from_secs(120);

/// Trait for implementing retryable RPC operations.
#[async_trait]
pub trait RetryableRpc {
    /// Execute an operation with retries using default timeout.
    async fn with_retry<'a, T, F, Fut>(&'a self, operation: F, operation_name: &str) -> Result<T>
    where
        F: Fn() -> Fut + Send + Sync + 'a,
        Fut: std::future::Future<Output = Result<T>> + Send,
        T: Send;

    /// Execute an operation with retries using custom timeout.
    async fn with_retry_timeout<'a, T, F, Fut>(
        &'a self,
        operation: F,
        timeout: Duration,
        operation_name: &str,
    ) -> Result<T>
    where
        F: Fn() -> Fut + Send + Sync + 'a,
        Fut: std::future::Future<Output = Result<T>> + Send,
        T: Send;
}

/// Execute an async operation with exponential backoff retries.
pub async fn retry_operation<T, F, Fut>(
    operation: F,
    timeout: Option<Duration>,
    operation_name: &str,
) -> Result<T>
where
    F: Fn() -> Fut + Send + Sync,
    Fut: std::future::Future<Output = Result<T>> + Send,
{
    let backoff = ExponentialBackoff {
        initial_interval: Duration::from_secs(1),
        max_interval: Duration::from_secs(120),
        max_elapsed_time: timeout,
        ..Default::default()
    };

    retry(backoff, || async {
        match operation().await {
            Ok(result) => Ok(result),
            Err(e) => {
                // Check for tonic status errors.
                if let Some(status) = e.downcast_ref::<tonic::Status>() {
                    match status.code() {
                        Code::Unavailable
                        | Code::DeadlineExceeded
                        | Code::Internal
                        | Code::Aborted => {
                            warn!(
                                "Network temporarily unavailable when {} due to {}, retrying...",
                                operation_name,
                                status.message(),
                            );
                            Err(BackoffError::transient(e))
                        }
                        Code::NotFound => {
                            error!("{} not found due to {}", operation_name, status.message(),);
                            Err(BackoffError::permanent(e))
                        }
                        _ => {
                            error!(
                                "Permanent error encountered when {}: {} ({})",
                                operation_name,
                                status.message(),
                                status.code()
                            );
                            Err(BackoffError::permanent(e))
                        }
                    }
                } else {
                    // Check for common transport errors.
                    let error_msg = e.to_string().to_lowercase();
                    let is_transient = error_msg.contains("tls handshake")
                        || error_msg.contains("dns error")
                        || error_msg.contains("connection reset")
                        || error_msg.contains("broken pipe")
                        || error_msg.contains("transport error")
                        || error_msg.contains("failed to lookup")
                        || error_msg.contains("timeout")
                        || error_msg.contains("deadline exceeded");

                    if is_transient {
                        warn!(
                            "Transient transport error when {}: {}, retrying...",
                            operation_name, error_msg
                        );
                        Err(BackoffError::transient(e))
                    } else {
                        error!("Permanent error when {}: {}", operation_name, error_msg);
                        Err(BackoffError::permanent(e))
                    }
                }
            }
        }
    })
    .await
}

#[async_trait]
impl RetryableRpc for ProverNetworkClient<Channel> {
    async fn with_retry<'a, T, F, Fut>(&'a self, operation: F, operation_name: &str) -> Result<T>
    where
        F: Fn() -> Fut + Send + Sync + 'a,
        Fut: std::future::Future<Output = Result<T>> + Send,
        T: Send,
    {
        self.with_retry_timeout(operation, DEFAULT_RETRY_TIMEOUT, operation_name).await
    }

    async fn with_retry_timeout<'a, T, F, Fut>(
        &'a self,
        operation: F,
        timeout: Duration,
        operation_name: &str,
    ) -> Result<T>
    where
        F: Fn() -> Fut + Send + Sync + 'a,
        Fut: std::future::Future<Output = Result<T>> + Send,
        T: Send,
    {
        retry_operation(operation, Some(timeout), operation_name).await
    }
}
