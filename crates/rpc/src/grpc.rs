use std::time::Duration;
use tonic::transport::{Endpoint, Error};

/// Configure an endpoint with appropriate timeouts and keep-alive settings.
pub fn configure_endpoint(addr: &str) -> Result<Endpoint, Error> {
    Ok(Endpoint::new(addr.to_string())?
        .timeout(Duration::from_secs(15))
        .connect_timeout(Duration::from_secs(15))
        .keep_alive_while_idle(true)
        .http2_keep_alive_interval(Duration::from_secs(15))
        .keep_alive_timeout(Duration::from_secs(15))
        .tcp_keepalive(Some(Duration::from_secs(30))))
}
