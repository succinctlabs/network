use std::time::Duration;

use anyhow::Result;
use async_trait::async_trait;
use spn_network_types::prover_network_client::ProverNetworkClient;
use tonic::transport::Channel;

use crate::retry::{retry_operation, RetryableRpc, DEFAULT_RETRY_TIMEOUT};

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
