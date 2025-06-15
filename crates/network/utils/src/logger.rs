use serde::Deserialize;
use tracing_subscriber::{
    fmt::{self},
    prelude::*,
    EnvFilter,
};

/// Format for log output.
#[derive(Debug, Deserialize, Clone, Copy)]
pub enum LogFormat {
    /// Human-readable pretty-printed format.
    Pretty,
    /// JSON format for structured logging.
    Json,
    /// Minimal format with only essential information.
    Minimal,
}

/// Initializes the logging system.
///
/// Filters out crate dependencies to reduce noise.
///
/// # Panics
///
/// Panics if any of the log filter directives fail to parse.
pub fn init_logger(log_format: LogFormat) {
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
        .add_directive("aws_smithy_http_client=warn".parse().unwrap())
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
        .add_directive("sp1_stark=warn".parse().unwrap())
        .add_directive("sp1_cuda=warn".parse().unwrap())
        .add_directive("p3_fri=warn".parse().unwrap())
        .add_directive("sp1_recursion_circuit=warn".parse().unwrap())
        .add_directive("sp1_recursion_compiler=warn".parse().unwrap())
        .add_directive("p3_merkle_tree=warn".parse().unwrap())
        .add_directive("p3_dft=warn".parse().unwrap())
        .add_directive("p3_uni_stark=warn".parse().unwrap())
        .add_directive("p3_keccak_air=warn".parse().unwrap())
        .add_directive("spn_artifacts=warn".parse().unwrap())
        .add_directive("sp1_circuit_compiler=warn".parse().unwrap());
    let base = tracing_subscriber::registry().with(filter);

    match log_format {
        LogFormat::Pretty => base
            .with(
                fmt::layer()
                    .pretty()
                    .with_file(false)
                    .with_target(false)
                    .with_line_number(false)
                    .with_thread_ids(false)
                    .with_thread_names(false),
            )
            .init(),
        LogFormat::Json => base.with(fmt::layer().json()).init(),
        LogFormat::Minimal => base.with(fmt::layer().with_level(true).compact()).init(),
    }
}
