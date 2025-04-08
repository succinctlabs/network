use serde::Deserialize;
use tracing_subscriber::{fmt, prelude::*, EnvFilter};

#[derive(Debug, Deserialize, Clone, Copy)]
pub enum LogFormat {
    Pretty,
    Json,
    Minimal,
}

/// Initializes the logging system.
///
/// Filters out crate dependencies to reduce noise.
pub fn init(log_format: LogFormat) {
    // Set default log level to info if RUST_LOG is not set.
    if std::env::var("RUST_LOG").is_err() {
        std::env::set_var("RUST_LOG", "info");
    }

    let filter = EnvFilter::from_default_env()
        .add_directive("aws_runtime=warn".parse().unwrap())
        .add_directive("aws_sdk_s3=warn".parse().unwrap())
        .add_directive("aws_sdk_sts=warn".parse().unwrap())
        .add_directive("aws_config=warn".parse().unwrap())
        .add_directive("aws_smithy_runtime=warn".parse().unwrap())
        .add_directive("hyper=warn".parse().unwrap())
        .add_directive("hyper_util=warn".parse().unwrap())
        .add_directive("tower=warn".parse().unwrap())
        .add_directive("tonic=warn".parse().unwrap())
        .add_directive("reqwest=warn".parse().unwrap())
        .add_directive("h2=warn".parse().unwrap())
        .add_directive("rustls=warn".parse().unwrap())
        .add_directive("sqlx=warn".parse().unwrap())
        .add_directive("rsp_rpc_db=warn".parse().unwrap())
        .add_directive("sp1_sdk=warn".parse().unwrap())
        .add_directive("sp1_prove=warn".parse().unwrap())
        .add_directive("sp1_prover=warn".parse().unwrap())
        .add_directive("sp1_core_machine=warn".parse().unwrap())
        .add_directive("sp1_core_executor=warn".parse().unwrap())
        .add_directive("sp1_cuda=warn".parse().unwrap());
    let base = tracing_subscriber::registry().with(filter);

    match log_format {
        LogFormat::Pretty => base.with(fmt::layer().pretty()).init(),
        LogFormat::Json => base.with(fmt::layer().json()).init(),
        LogFormat::Minimal => base
            .with(
                fmt::layer()
                    .with_target(false)
                    .with_line_number(false)
                    .with_file(false)
                    .with_thread_ids(false)
                    .with_thread_names(false)
                    .with_level(true)
                    .compact(),
            )
            .init(),
    }
}
