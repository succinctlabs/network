//! Structured, sanitized error traces for failed proof requests.
//!
//! When a proof request fails, the producer (the SPN external prover, the
//! executor, or the cluster fulfiller) builds an [`ErrorTrace`], redacts secrets,
//! bounds its size, and ships it on `FailFulfillmentRequestBody.error_trace` or
//! `ExecuteProofRequestBody.error_trace`. The RPC service does NOT trust that
//! sanitization: [`sanitize_wire_trace`] re-parses the bytes into the canonical
//! type, re-runs [`ErrorTrace::finalize`], and stores only the sanitized
//! canonical JSON in the `requests.error_trace` JSONB column.
//!
//! The goal is to replace opaque "Unknown Error" failures with enough bounded,
//! non-sensitive context to debug cluster bugs and customer program panics —
//! without storing massive logs, secrets, or raw customer inputs.
//!
//! This module is dependency-light on purpose: it is consumed by the open-source
//! `sp1-cluster` fulfiller (via the `spn-network-types` git dependency on this
//! repo), so it must not pull in heavy or platform-specific crates. Sanitization
//! is implemented with plain string scanning rather than `regex` to avoid a new
//! dependency.
//!
//! SYNC: this is a manually-kept duplicate of the canonical module in
//! `succinctlabs/network-services` (PR #1191). The two proto repos are not
//! auto-synced; `FailFulfillmentRequestBody.error_trace` is wire field 4 and
//! `ExecuteProofRequestBody.error_trace` is wire field 11 in both repos. Keep
//! this file and its network-services twin logically identical — change them
//! together.

use serde::{Deserialize, Serialize};

/// Schema version of the [`ErrorTrace`] payload. Bump on breaking shape changes.
pub const ERROR_TRACE_VERSION: u32 = 1;

/// Maximum bytes for the one-line `message` summary.
pub const MESSAGE_MAX: usize = 4 * 1024;
/// Maximum bytes for the `details` cause chain.
pub const DETAILS_MAX: usize = 16 * 1024;
/// Maximum bytes for a captured `stderr_excerpt`.
pub const STDERR_EXCERPT_MAX: usize = 8 * 1024;
/// Maximum bytes for a captured `stack_trace`.
pub const STACK_TRACE_MAX: usize = 16 * 1024;
/// Hard cap on the serialized JSON payload, enforced after assembly. Fields are
/// dropped in priority order (stack_trace > stderr_excerpt > details) to fit.
pub const TOTAL_JSON_MAX: usize = 32 * 1024;
/// Defensive upper bound the RPC service accepts off the wire before parsing.
/// Generously larger than [`TOTAL_JSON_MAX`]; anything bigger is dropped.
pub const WIRE_BYTES_MAX: usize = 64 * 1024;
/// Cap for the small identifier/timestamp fields (request_id, job_id, cluster_id,
/// timestamp). Keeps them from being abused to smuggle large or unbounded data.
pub const ID_FIELD_MAX: usize = 256;

/// Where the failure originated.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorSource {
    /// A cluster/prover-side failure (e.g. a failed proving task).
    Cluster,
    /// The SP1 executor failed to execute the program.
    Executor,
    /// The guest program itself panicked / halted with a non-zero exit code.
    Program,
    /// The SPN external prover binary (the standalone proving bridge).
    Bridge,
    /// Source could not be determined.
    Unknown,
}

/// The class of failure.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorKind {
    /// The guest program panicked or exited non-zero.
    ProgramPanic,
    /// The executor/runtime errored (cycle limit, bad syscall, memory, ...).
    ExecutorError,
    /// A cluster/prover-side error after the request was executed.
    ClusterError,
    /// Class could not be determined.
    Unknown,
}

/// Panic location/message details, when available.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct PanicInfo {
    /// The panic message / payload.
    pub message: String,
    /// `file:line:column` of the panic, when captured.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub location: Option<String>,
}

/// A bounded, sanitized, structured description of why a proof request failed.
///
/// Construct via [`ErrorTrace::from_cluster_extra_data`] or
/// [`ErrorTrace::from_bridge_error`], attach context with `with_request_id` or by
/// setting optional fields directly,
/// then call [`ErrorTrace::finalize`] (sanitize + bound + drop-if-useless) and
/// [`ErrorTrace::to_wire_bytes`] (serialize + total-size cap).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ErrorTrace {
    /// Schema version; see [`ERROR_TRACE_VERSION`].
    pub version: u32,
    /// Where the failure originated.
    pub source: ErrorSource,
    /// The class of failure.
    pub kind: ErrorKind,
    /// A short, human-readable summary (bounded by [`MESSAGE_MAX`]).
    pub message: String,
    /// Fuller cause chain / detail (bounded by [`DETAILS_MAX`]).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
    /// The proving/execution phase (e.g. "execution", "proving").
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub phase: Option<String>,
    /// The guest program exit code, when known.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i64>,
    /// A bounded excerpt of captured stderr (bounded by [`STDERR_EXCERPT_MAX`]).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stderr_excerpt: Option<String>,
    /// A bounded, boilerplate-stripped stack trace (bounded by [`STACK_TRACE_MAX`]).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub stack_trace: Option<String>,
    /// Panic details, when the failure was a panic.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub panic: Option<PanicInfo>,
    /// The failing request id (hex), for cross-referencing.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub request_id: Option<String>,
    /// The cluster job/proof id, when available.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub job_id: Option<String>,
    /// The cluster id, when available.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub cluster_id: Option<String>,
    /// RFC3339 timestamp set by the producer at authoring time.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub timestamp: Option<String>,
}

impl ErrorTrace {
    /// Create a new trace with the required fields. Optional fields start empty.
    pub fn new(source: ErrorSource, kind: ErrorKind, message: impl Into<String>) -> Self {
        Self {
            version: ERROR_TRACE_VERSION,
            source,
            kind,
            message: message.into(),
            details: None,
            phase: None,
            exit_code: None,
            stderr_excerpt: None,
            stack_trace: None,
            panic: None,
            request_id: None,
            job_id: None,
            cluster_id: None,
            timestamp: None,
        }
    }

    /// Attach the request id (hex string).
    pub fn with_request_id(mut self, request_id: impl Into<String>) -> Self {
        self.request_id = Some(request_id.into());
        self
    }

    /// Build a trace from a cluster `extra_data` wire string.
    ///
    /// Handles the two shapes the cluster writes today:
    /// 1. `{"proving_failure": {"task_type": <int>, "reason": "<string>"}}` (post-execute proving
    ///    task failures), and
    /// 2. the `ExecutionResult` object `{"status": <int>, "failure_cause": <int>, ...}`
    ///    (execute-only).
    ///
    /// Returns `None` when `extra_data` is absent/empty or carries no failure
    /// signal (e.g. a successful execution result). The returned trace is *not*
    /// yet finalized — call [`ErrorTrace::finalize`] before serializing.
    pub fn from_cluster_extra_data(extra_data: Option<&str>) -> Option<Self> {
        let raw = extra_data.map(str::trim).filter(|s| !s.is_empty() && *s != "{}")?;

        // Shape 1: proving failure envelope.
        if let Some(pf) = parse_proving_failure(raw) {
            let reason = pf.reason.trim();
            let (message, details) = split_summary_and_details(reason);
            let mut trace = ErrorTrace::new(ErrorSource::Cluster, ErrorKind::ClusterError, message);
            trace.details = details;
            trace.phase = Some(match &pf.task_type {
                Some(task_type) => format!("proving (task_type {task_type})"),
                None => "proving".to_string(),
            });
            return Some(trace);
        }

        // Shape 2: execution result. The typed `failure_cause` drives the
        // source/kind; optional enrichment (`failure_message`, `exit_code`)
        // improves the message/details when the producer supplies it.
        if let Some(er) = parse_execution_result(raw) {
            let msg = er.failure_message.as_deref().map(str::trim).filter(|s| !s.is_empty());
            let mut trace = match Self::from_execute_failure_cause(er.failure_cause as i32) {
                Some(trace) => trace,
                // Unspecified(0) cause carries no signal on its own, but the producer
                // may still attach a failure_message (e.g. an unmapped
                // Err(ExecutionError)). Surface it as an execution-phase executor error
                // rather than dropping it; finalize() drops generic/empty text.
                None if msg.is_some() => {
                    let mut trace = ErrorTrace::new(
                        ErrorSource::Executor,
                        ErrorKind::ExecutorError,
                        "execution failed",
                    );
                    trace.phase = Some("execution".to_string());
                    trace
                }
                None => return None,
            };
            if let Some(code) = er.exit_code {
                trace.exit_code = Some(code);
            }
            if let Some(msg) = msg {
                let (message, details) = split_summary_and_details(msg);
                trace.message = message;
                trace.details = details;
            }
            return Some(trace);
        }

        // Unknown shape: keep the raw string as a best-effort message rather than
        // dropping it. `finalize` will sanitize/bound it (and omit if useless).
        let (message, details) = split_summary_and_details(raw);
        let mut trace = ErrorTrace::new(ErrorSource::Cluster, ErrorKind::Unknown, message);
        trace.details = details;
        Some(trace)
    }

    /// Build a trace from a typed `ExecuteFailureCause` integer code (the SPN
    /// executor only carries the enum, not the cluster's free-form `extra_data`).
    /// Maps `HaltWithNonZeroExitCode` to a guest program panic and every other
    /// cause to an executor error. Returns `None` for the unspecified/zero cause
    /// (no useful signal). The returned trace is *not* yet finalized.
    pub fn from_execute_failure_cause(cause: i32) -> Option<Self> {
        if cause == 0 {
            return None;
        }
        let name = execute_failure_cause_name(cause as i64);
        let (kind, source) = if cause == 1 {
            // HaltWithNonZeroExitCode == guest program panicked / exited non-zero.
            (ErrorKind::ProgramPanic, ErrorSource::Program)
        } else {
            (ErrorKind::ExecutorError, ErrorSource::Executor)
        };
        let mut trace = ErrorTrace::new(source, kind, format!("execution failed: {name}"));
        trace.phase = Some("execution".to_string());
        Some(trace)
    }

    /// Build a trace from the SPN external prover's captured error string.
    ///
    /// The bridge formats failures as either `"{error}"` or
    /// `"{error}\nPanic details:\n{panic block}"`. The panic block can take any of
    /// the forms `ErrorCapture` / the std panic Display emit (see
    /// [`parse_panic_block`]): `"panic occurred at {loc}: {payload}"`, the std
    /// two-line `"panicked at {loc}:\n{payload}"`, or a bare payload. Panic
    /// location/message are extracted into the structured `panic` field; the
    /// failure is classified `ProgramPanic` only when a panic marker is found.
    /// The returned trace is not yet finalized.
    pub fn from_bridge_error(error_str: &str) -> Self {
        const PANIC_MARKER: &str = "\nPanic details:\n";
        let (head, block) = match error_str.find(PANIC_MARKER) {
            Some(idx) => {
                (error_str[..idx].trim(), Some(error_str[idx + PANIC_MARKER.len()..].trim()))
            }
            None => (error_str.trim(), None),
        };

        // Prefer the explicit panic block; otherwise detect an inline std panic
        // marker in the head (some paths emit it without the wrapper).
        let panic = block.and_then(parse_panic_block).or_else(|| {
            if head.contains("panicked at ") || head.contains("panic occurred at ") {
                parse_panic_block(head)
            } else {
                None
            }
        });

        let kind = if panic.is_some() { ErrorKind::ProgramPanic } else { ErrorKind::ExecutorError };
        let (message, details) = split_summary_and_details(head);
        let mut trace = ErrorTrace::new(ErrorSource::Bridge, kind, message);
        trace.details = details;
        trace.panic = panic;
        trace
    }

    /// Sanitize (redact secrets, strip boilerplate) and bound every text field,
    /// then decide whether the trace carries useful context.
    ///
    /// Returns `None` when the trace would amount to junk (e.g. a bare "Unknown
    /// Error" with no other signal), so the caller stores `NULL` rather than a
    /// useless blob.
    pub fn finalize(mut self) -> Option<Self> {
        self.message = truncate_bytes(sanitize(&self.message), MESSAGE_MAX);
        self.details = self
            .details
            .map(|d| truncate_bytes(sanitize(&d), DETAILS_MAX))
            .filter(|d| !d.trim().is_empty());
        self.stderr_excerpt = self
            .stderr_excerpt
            .map(|s| truncate_bytes(sanitize(&s), STDERR_EXCERPT_MAX))
            .filter(|s| !s.trim().is_empty());
        self.stack_trace = self
            .stack_trace
            .map(|s| truncate_bytes(strip_stack_boilerplate(&sanitize(&s)), STACK_TRACE_MAX))
            .filter(|s| !s.trim().is_empty());
        self.phase = self.phase.map(|p| truncate_bytes(sanitize(&p), MESSAGE_MAX));
        if let Some(p) = self.panic.take() {
            let message = truncate_bytes(sanitize(&p.message), MESSAGE_MAX);
            let location = p.location.map(|l| truncate_bytes(sanitize(&l), 512));
            // Drop an empty panic block entirely.
            if !message.trim().is_empty() || location.is_some() {
                self.panic = Some(PanicInfo { message, location });
            }
        }

        // Identifier/timestamp fields are caller-supplied: sanitize and tightly
        // bound them too, so a future caller can't smuggle secrets or unbounded
        // data through them (they bypass the per-field text caps above).
        let bound_id = |s: Option<String>| s.map(|v| truncate_bytes(sanitize(&v), ID_FIELD_MAX));
        self.request_id = bound_id(self.request_id);
        self.job_id = bound_id(self.job_id);
        self.cluster_id = bound_id(self.cluster_id);
        self.timestamp = bound_id(self.timestamp);

        // Avoid storing a `details` that merely duplicates `message`.
        if self.details.as_deref().map(str::trim) == Some(self.message.trim()) {
            self.details = None;
        }

        if self.is_useful() {
            Some(self)
        } else {
            None
        }
    }

    /// Whether the (finalized) trace carries debuggable signal beyond a generic
    /// "unknown" message.
    fn is_useful(&self) -> bool {
        let msg = self.message.trim();
        let lower = msg.to_lowercase();
        // Treat very short or canonically-generic messages as carrying no signal.
        let generic = lower.is_empty()
            || msg.chars().count() <= 2
            || matches!(
                lower.as_str(),
                "unknown error"
                    | "unknown"
                    | "unknown failure"
                    | "unspecified"
                    | "unspecifiedproofrequestfailure"
                    | "unknownfailure"
                    | "error"
                    | "error:"
                    | "failed"
                    | "failure"
                    | "panic"
                    | "panicked"
                    | "internal error"
                    | "some(error)"
                    | "n/a"
                    | "none"
                    | "null"
            );
        !generic
            || self.details.is_some()
            || self.panic.is_some()
            || self.stderr_excerpt.is_some()
            || self.stack_trace.is_some()
            || self.exit_code.is_some()
    }

    /// Serialize to JSON bytes for the wire / for storage, enforcing
    /// [`TOTAL_JSON_MAX`]. If over the cap, drops the largest optional fields in
    /// priority order (stack_trace > stderr_excerpt > details) before giving up
    /// and truncating. Returns `None` only if serialization itself fails.
    pub fn to_wire_bytes(&self) -> Option<Vec<u8>> {
        let mut candidate = self.clone();
        for drop_stage in 0..=3 {
            let bytes = serde_json::to_vec(&candidate).ok()?;
            if bytes.len() <= TOTAL_JSON_MAX {
                return Some(bytes);
            }
            match drop_stage {
                0 => candidate.stack_trace = None,
                1 => candidate.stderr_excerpt = None,
                2 => candidate.details = None,
                _ => {
                    // Last resort: hard-truncate the message and emit.
                    candidate.message =
                        truncate_bytes(std::mem::take(&mut candidate.message), TOTAL_JSON_MAX / 2);
                    return serde_json::to_vec(&candidate).ok();
                }
            }
        }
        serde_json::to_vec(&candidate).ok()
    }

    /// Convenience: serialize to a [`serde_json::Value`] (no size enforcement).
    ///
    /// Serialization is infallible for this type (only owned strings, enums,
    /// integers, and `Option`s — no maps with non-string keys or fallible
    /// `Serialize` impls), so a failure here is a programming error, not a
    /// runtime condition to paper over with a null.
    pub fn to_json_value(&self) -> serde_json::Value {
        serde_json::to_value(self).expect("ErrorTrace serializes to JSON")
    }
}

/// Defensive RPC-side ingestion of an `error_trace` wire payload.
///
/// SPN does NOT trust the producer's sanitization. The bytes are parsed into the
/// canonical [`ErrorTrace`], re-run through [`ErrorTrace::finalize`] (which
/// redacts secrets, bounds every field, strips boilerplate, and drops useless
/// traces), and re-serialized through [`ErrorTrace::to_wire_bytes`] (total-size
/// cap). Only the resulting sanitized *canonical* JSON is stored — any unknown
/// fields a producer tacked on are dropped, and any secret in a recognized field
/// is redacted, no matter what the producer sent over the wire.
///
/// Returns `None` (store `NULL`) — never failing the RPC — for anything that is
/// empty, oversized (> [`WIRE_BYTES_MAX`]), not valid UTF-8 JSON, not a canonical
/// `ErrorTrace` object (arrays, strings, numbers, `{}`, unknown/invalid schema),
/// or that finalizes to a useless trace (e.g. a bare "Unknown Error").
pub fn sanitize_wire_trace(bytes: &[u8]) -> Option<serde_json::Value> {
    if bytes.is_empty() || bytes.len() > WIRE_BYTES_MAX {
        return None;
    }
    // Parse into the canonical type. This rejects arrays/strings/numbers, empty
    // or schema-invalid objects, and non-UTF-8/non-JSON bytes outright.
    let trace: ErrorTrace = serde_json::from_slice(bytes).ok()?;
    // Re-sanitize, re-bound, and drop-if-useless regardless of producer behavior.
    let canonical = trace.finalize()?.to_wire_bytes()?;
    // Re-parse our own canonical output into a Value for JSONB storage.
    serde_json::from_slice(&canonical).ok()
}

// ---------------------------------------------------------------------------
// Cluster `extra_data` parsing helpers
// ---------------------------------------------------------------------------

/// The `task_type` in a cluster `proving_failure` envelope. The real producer
/// serializes the `TaskType` proto enum as its variant-name string (e.g.
/// `"ProveShard"`); older/synthetic payloads use the integer discriminant.
/// Accept either so the structured trace is populated from the real wire shape.
#[derive(Deserialize)]
#[serde(untagged)]
enum TaskType {
    Name(String),
    Code(i64),
}

impl std::fmt::Display for TaskType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TaskType::Name(s) => f.write_str(s),
            TaskType::Code(c) => write!(f, "{c}"),
        }
    }
}

#[derive(Deserialize)]
struct ProvingFailurePayload {
    #[serde(default)]
    task_type: Option<TaskType>,
    #[serde(default)]
    reason: String,
}

fn parse_proving_failure(raw: &str) -> Option<ProvingFailurePayload> {
    #[derive(Deserialize)]
    struct Envelope {
        proving_failure: ProvingFailurePayload,
    }
    serde_json::from_str::<Envelope>(raw).ok().map(|e| e.proving_failure)
}

#[derive(Deserialize)]
struct ExecutionResultPayload {
    #[serde(default)]
    failure_cause: i64,
    /// Additive enrichment from newer producers: a bounded, human-readable detail
    /// string for `Err(ExecutionError)` execute-only failures. Absent on older
    /// producers and on guest-panic (`HaltWithNonZeroExitCode`) failures.
    #[serde(default)]
    failure_message: Option<String>,
    /// Additive enrichment from newer producers: the guest exit code for non-zero
    /// halt failures. Absent on older producers.
    #[serde(default)]
    exit_code: Option<i64>,
}

fn parse_execution_result(raw: &str) -> Option<ExecutionResultPayload> {
    // Only treat as an execution result if the field is actually present, so an
    // unrelated object doesn't get mistaken for one.
    let value: serde_json::Value = serde_json::from_str(raw).ok()?;
    if value.get("failure_cause").is_some() {
        serde_json::from_value(value).ok()
    } else {
        None
    }
}

/// Map an `ExecuteFailureCause` integer code to a stable, non-sensitive name.
/// Mirrors `spn_network_types::ExecuteFailureCause` ordering.
fn execute_failure_cause_name(code: i64) -> &'static str {
    match code {
        1 => "HaltWithNonZeroExitCode",
        2 => "InvalidMemoryAccess",
        3 => "UnsupportedSyscall",
        4 => "Breakpoint",
        5 => "ExceededCycleLimit",
        6 => "InvalidSyscallUsage",
        7 => "Unimplemented",
        8 => "EndInUnconstrained",
        9 => "ExceededGasLimit",
        _ => "UnspecifiedExecutionFailureCause",
    }
}

/// Parse a panic block into [`PanicInfo`], handling every form the prover can
/// emit (possibly nested):
///   - `"panic occurred at {loc}: {payload}"`     (ErrorCapture wrapper)
///   - `"panicked at {loc}:\n{payload}"`          (std panic Display, Rust >= 1.65)
///   - `"panic occurred at {loc}: panicked at {loc}:\n{payload}"` (wrapper + std)
///   - a bare `{payload}` with no marker.
///
/// Returns `None` only for an empty block.
fn parse_panic_block(block: &str) -> Option<PanicInfo> {
    let block = block.trim();
    if block.is_empty() {
        return None;
    }
    // Peel off any "panic occurred at " / "panicked at " markers (the std form may
    // be nested inside our wrapper) until we're left with "{loc}{sep}{payload}".
    let mut rest = block;
    let mut had_marker = false;
    loop {
        let trimmed = rest.trim_start();
        if let Some(s) = trimmed.strip_prefix("panic occurred at ") {
            rest = s;
            had_marker = true;
            continue;
        }
        if let Some(s) = trimmed.strip_prefix("panicked at ") {
            rest = s;
            had_marker = true;
            continue;
        }
        // Jump to a nested "panicked at " marker if the text before it is a single
        // line (i.e. a location fragment, not the payload yet).
        if let Some(pos) = trimmed.find("panicked at ") {
            if !trimmed[..pos].contains('\n') {
                rest = &trimmed[pos + "panicked at ".len()..];
                had_marker = true;
                continue;
            }
        }
        rest = trimmed;
        break;
    }

    if had_marker {
        Some(split_loc_and_payload(rest))
    } else {
        Some(PanicInfo { message: block.to_string(), location: None })
    }
}

/// Split `"{loc}{sep}{payload}"` into a [`PanicInfo`]. The payload may follow the
/// location on the next line (std two-line form) or after `": "` (single line).
fn split_loc_and_payload(s: &str) -> PanicInfo {
    let s = s.trim();
    if let Some(nl) = s.find(":\n") {
        return PanicInfo {
            location: Some(s[..nl].trim().to_string()),
            message: s[nl + 2..].trim().to_string(),
        };
    }
    if let Some((loc, msg)) = s.split_once(": ") {
        return PanicInfo {
            location: Some(loc.trim().to_string()),
            message: msg.trim().to_string(),
        };
    }
    // Only a location, no payload.
    PanicInfo { message: String::new(), location: Some(s.trim_end_matches(':').to_string()) }
}

/// Split a (possibly multi-line) error string into a one-line `message` summary
/// and an optional fuller `details`. The first non-empty line is the summary;
/// the remainder (if any) is details.
fn split_summary_and_details(text: &str) -> (String, Option<String>) {
    let text = text.trim();
    if text.is_empty() {
        return (String::new(), None);
    }
    match text.split_once('\n') {
        Some((first, rest)) => {
            let rest = rest.trim();
            let details = if rest.is_empty() { None } else { Some(text.to_string()) };
            (first.trim().to_string(), details)
        }
        None => (text.to_string(), None),
    }
}

// ---------------------------------------------------------------------------
// Sanitization (redaction + boilerplate stripping), regex-free.
// ---------------------------------------------------------------------------

/// Token marker substituted for redacted content.
const REDACTED: &str = "[REDACTED]";

/// Sensitive key names (lowercased substrings). When one appears as the key of a
/// `key=value` (or `key: value`) pair, the value is redacted.
const SENSITIVE_KEYS: &[&str] = &[
    "password",
    "passwd",
    "secret",
    "private_key",
    "privatekey",
    "priv_key",
    "api_key",
    "apikey",
    "access_key",
    "accesskey",
    "secret_key",
    "secretkey",
    "token",
    "authorization",
    "mnemonic",
    "seed_phrase",
    "seed",
    "signing_key",
    "signingkey",
    "keystore",
    "credential",
    "cookie",
    "database_url",
    "redis_url",
    "aws_secret_access_key",
];

/// Redact secrets and strip ANSI from an arbitrary error/log string.
///
/// Processes line by line; within each line, collapses runs of whitespace and
/// applies per-token redaction. This deliberately favors over-redaction of
/// credential-shaped tokens over leaking them. Bare 64-hex strings (request ids,
/// vk hashes, tx hashes) are *not* redacted — only values adjacent to a
/// sensitive key label are.
pub fn sanitize(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for (i, line) in input.lines().enumerate() {
        if i > 0 {
            out.push('\n');
        }
        out.push_str(&sanitize_line(line));
    }
    out
}

fn sanitize_line(line: &str) -> String {
    let line = strip_ansi(line);
    let tokens: Vec<&str> = line.split_whitespace().collect();
    let mut out: Vec<String> = Vec::with_capacity(tokens.len());
    let mut i = 0;
    while i < tokens.len() {
        let token = tokens[i];

        // Intra-token redaction (URL query, AWS key, conn-string creds,
        // key=value / key:value). Computed up front but applied below so it
        // composes with the cross-token carry-over.
        let redacted = redact_token(token);

        // Cross-token carry-over: a sensitive label whose secret lands in a
        // FOLLOWING token, e.g. "Authorization: Bearer <tok>", "password = <x>",
        // or the JSON shape `"authorization":"Bearer <jwt>`. Evaluated on the
        // ORIGINAL token so an in-token redaction (e.g. of the "Bearer" scheme
        // word) doesn't hide the fact that the real secret is the next token.
        if secret_value_follows(token, tokens.get(i + 1).copied()) {
            out.push(redacted);
            let mut j = i + 1;
            // Skip lone connectors and chained scheme words (e.g. the "Bearer"/
            // "Basic" in "Authorization: Bearer <tok>" / "Authorization: Basic
            // <creds>") so the redaction lands on the actual credential.
            while j < tokens.len()
                && (tokens[j] == "="
                    || tokens[j] == ":"
                    || is_auth_label(tokens[j])
                    || is_auth_scheme_word(tokens[j]))
            {
                out.push(tokens[j].to_string());
                j += 1;
            }
            if j < tokens.len() {
                out.push(REDACTED.to_string());
                j += 1;
                // Multi-value headers (e.g. cookies: "a=1; b=2") put more secrets
                // in following `name=value` tokens whose names aren't sensitive;
                // keep redacting them so later pairs don't leak.
                while j < tokens.len() && token_is_kv_pair(tokens[j]) {
                    out.push(REDACTED.to_string());
                    j += 1;
                }
            }
            i = j;
            continue;
        }

        out.push(redacted);
        i += 1;
    }
    out.join(" ")
}

fn redact_token(token: &str) -> String {
    // 0. Presigned-URL signing params anywhere in the token. reqwest renders a
    //    transport error as `error sending request for url (https://...?X-Amz-...)`,
    //    so the URL is wrapped in punctuation and prefix checks miss it — match the
    //    signing params directly as a defense in depth.
    let lower = token.to_lowercase();
    if lower.contains("x-amz-signature")
        || lower.contains("x-amz-credential")
        || lower.contains("x-amz-security-token")
        || lower.contains("&signature=")
        || lower.contains("?signature=")
    {
        if let Some(scheme) = token.find("://") {
            if let Some(q) = token[scheme..].find('?') {
                return format!("{}?{REDACTED}", &token[..scheme + q]);
            }
        }
        return REDACTED.to_string();
    }

    // 1. Connection strings with embedded credentials: scheme://user:pass@host
    if let Some(scheme_end) = token.find("://") {
        let after = &token[scheme_end + 3..];
        if let Some(at) = after.find('@') {
            let creds = &after[..at];
            if creds.contains(':') {
                let scheme = &token[..scheme_end + 3];
                let rest = &after[at..];
                return format!("{scheme}{REDACTED}{rest}");
            }
        }
        // 2. URLs (incl. presigned S3): drop the query string regardless of any surrounding
        //    punctuation — match `://` anywhere, not as a prefix.
        if let Some(q) = token[scheme_end..].find('?') {
            return format!("{}?{REDACTED}", &token[..scheme_end + q]);
        }
    }

    // 3. AWS access key ids (AKIA/ASIA + 16 upper-alnum) anywhere in the token, even surrounded by
    //    punctuation (commas, quotes, parens, path separators).
    if let Some(redacted) = redact_aws_keys(token) {
        return redacted;
    }

    // 4. `key=value` where the key is sensitive.
    if let Some((key, value)) = token.split_once('=') {
        if !value.is_empty() && key_is_sensitive(key) {
            return format!("{key}={REDACTED}");
        }
    }
    // 5. `key:value` (no space) where the key is sensitive. The key gate decides (so base64/JWT
    //    secrets containing '/' are still redacted); a numeric value is treated as `file:line:col`
    //    and left alone.
    if let Some((key, value)) = token.split_once(':') {
        let first_seg = value.split(':').next().unwrap_or(value);
        let looks_like_line_number =
            !first_seg.is_empty() && first_seg.bytes().all(|b| b.is_ascii_digit());
        if !value.is_empty() && !looks_like_line_number && key_is_sensitive(key) {
            return format!("{key}:{REDACTED}");
        }
    }

    token.to_string()
}

/// Redact AWS access key ids (`AKIA`/`ASIA` + 16 upper-alnum) occurring anywhere
/// within `token`, returning `Some(redacted)` only if a key matched. Operates on
/// bytes (all key chars are ASCII) so it never panics on multibyte input.
fn redact_aws_keys(token: &str) -> Option<String> {
    let bytes = token.as_bytes();
    let mut out = String::with_capacity(token.len());
    let mut i = 0;
    let mut found = false;
    while i < bytes.len() {
        let is_key = i + 20 <= bytes.len()
            && bytes[i] == b'A'
            && (bytes[i + 1] == b'K' || bytes[i + 1] == b'S')
            && bytes[i + 2] == b'I'
            && bytes[i + 3] == b'A'
            && bytes[i + 4..i + 20].iter().all(|&b| b.is_ascii_uppercase() || b.is_ascii_digit())
            && (i == 0 || !is_key_char(bytes[i - 1]))
            && (i + 20 == bytes.len() || !is_key_char(bytes[i + 20]));
        if is_key {
            out.push_str("[REDACTED-AWS-KEY]");
            i += 20;
            found = true;
        } else {
            let ch_len = utf8_len(bytes[i]);
            let end = (i + ch_len).min(bytes.len());
            out.push_str(std::str::from_utf8(&bytes[i..end]).unwrap_or(""));
            i = end;
        }
    }
    if found {
        Some(out)
    } else {
        None
    }
}

fn is_key_char(b: u8) -> bool {
    b.is_ascii_uppercase() || b.is_ascii_digit()
}

/// Whether `token` is an `Authorization`/`Bearer` label (allowing a trailing
/// `:`/`=` and surrounding quotes).
fn is_auth_label(token: &str) -> bool {
    let t = token.trim_end_matches([':', '=']).trim_matches(['"', '\'']);
    t.eq_ignore_ascii_case("authorization") || t.eq_ignore_ascii_case("bearer")
}

/// Whether `token` names a secret whose value lands in a *following* token rather
/// than within `token` itself. Covers:
///   - auth scheme labels ("Authorization", "Bearer");
///   - a bare sensitive key immediately followed by an `=`/`:` connector token;
///   - a `key:value`/`key=value` whose in-token value is empty or just an auth scheme word (e.g.
///     `"authorization":"Bearer` before the real JWT token).
///
/// It does NOT trigger when the in-token value is the actual secret (e.g.
/// `password=hunter2`), to avoid eating unrelated following words.
fn secret_value_follows(token: &str, next: Option<&str>) -> bool {
    if is_auth_label(token) {
        return true;
    }
    match split_key_value(token) {
        // Bare sensitive key: carry over only when an explicit connector follows
        // (so prose like "the password was wrong" isn't over-redacted).
        None => {
            key_is_sensitive(token.trim_end_matches([':', '=']))
                && matches!(next, Some("=") | Some(":"))
        }
        // `key=value` / `key:value`: carry over only when the in-token value is
        // empty or a bare auth scheme (the real credential is the next token).
        Some((key, value)) => {
            if !key_is_sensitive(key) {
                return false;
            }
            let v = value.trim().trim_matches(['"', '\'']).trim();
            v.is_empty() || is_auth_scheme_word(v)
        }
    }
}

/// A bare HTTP auth scheme word (the part before the actual credential), e.g.
/// `Bearer`, `Basic`, `Digest`. Used both to detect that a credential follows in
/// the next token and to skip the scheme word when redacting it.
fn is_auth_scheme_word(token: &str) -> bool {
    let t = token.trim_matches(['"', '\'']);
    matches!(
        t.to_ascii_lowercase().as_str(),
        "bearer" | "basic" | "digest" | "negotiate" | "ntlm" | "token"
    )
}

/// Whether the token looks like a `name=value` pair (a non-empty name before a
/// `=`). Used to keep redacting trailing pairs in multi-value headers (cookies).
fn token_is_kv_pair(token: &str) -> bool {
    matches!(token.split_once('='), Some((name, _)) if !name.is_empty())
}

/// Split a token into `(key, value)` on the first `=` or `:` separator, if any.
fn split_key_value(token: &str) -> Option<(&str, &str)> {
    let sep = match (token.find('='), token.find(':')) {
        (Some(a), Some(b)) => a.min(b),
        (Some(a), None) => a,
        (None, Some(b)) => b,
        (None, None) => return None,
    };
    Some((&token[..sep], &token[sep + 1..]))
}

fn key_is_sensitive(key: &str) -> bool {
    // Normalize hyphen/underscore so `x-api-key` matches `api_key`, etc.
    let key = key.trim().trim_matches(['"', '\'']).to_lowercase().replace('-', "_");
    SENSITIVE_KEYS.iter().any(|s| key.contains(s))
}

/// Remove ANSI/VT100 escape sequences (e.g. color codes) from a line.
fn strip_ansi(line: &str) -> String {
    let bytes = line.as_bytes();
    let mut out = String::with_capacity(line.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == 0x1b && i + 1 < bytes.len() && bytes[i + 1] == b'[' {
            i += 2;
            // Skip until a final byte in the 0x40..=0x7e range.
            while i < bytes.len() && !(0x40..=0x7e).contains(&bytes[i]) {
                i += 1;
            }
            if i < bytes.len() {
                i += 1; // consume the final byte
            }
        } else {
            // Copy this UTF-8 scalar verbatim.
            let ch_len = utf8_len(bytes[i]);
            let end = (i + ch_len).min(bytes.len());
            if let Ok(s) = std::str::from_utf8(&bytes[i..end]) {
                out.push_str(s);
            }
            i = end;
        }
    }
    out
}

fn utf8_len(first: u8) -> usize {
    match first {
        b if b < 0x80 => 1,
        b if b >> 5 == 0b110 => 2,
        b if b >> 4 == 0b1110 => 3,
        b if b >> 3 == 0b11110 => 4,
        _ => 1,
    }
}

/// Strip low-value backtrace boilerplate from a stack trace: pure std/runtime
/// frames, `note: run with RUST_BACKTRACE` lines, and collapse blank runs.
fn strip_stack_boilerplate(stack: &str) -> String {
    let mut out_lines: Vec<&str> = Vec::new();
    let mut blanks = 0;
    for line in stack.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            blanks += 1;
            if blanks <= 1 {
                out_lines.push(line);
            }
            continue;
        }
        blanks = 0;
        let lower = trimmed.to_lowercase();
        if lower.starts_with("note: run with")
            || lower == "stack backtrace:"
            || is_std_frame(trimmed)
        {
            continue;
        }
        out_lines.push(line);
    }
    out_lines.join("\n").trim().to_string()
}

/// Heuristic: a backtrace frame purely in std/runtime crates (not our code).
fn is_std_frame(line: &str) -> bool {
    // Frames look like "  12: core::panicking::panic_fmt".
    let after_num =
        line.trim_start().split_once(':').map(|(_, rest)| rest.trim()).unwrap_or(line.trim());
    const STD_PREFIXES: &[&str] = &[
        "core::",
        "std::",
        "alloc::",
        "tokio::",
        "<core::",
        "<std::",
        "<alloc::",
        "__rust_",
        "rust_begin_unwind",
        "backtrace::",
        "std::panicking",
        "std::rt",
    ];
    STD_PREFIXES.iter().any(|p| after_num.starts_with(p))
}

/// Truncate a string to at most `max` bytes on a UTF-8 char boundary, appending
/// a marker noting how many bytes were dropped.
fn truncate_bytes(mut s: String, max: usize) -> String {
    if s.len() <= max {
        return s;
    }
    let dropped = s.len() - max;
    // Walk back to a char boundary at or below `max`.
    let mut cut = max;
    while cut > 0 && !s.is_char_boundary(cut) {
        cut -= 1;
    }
    s.truncate(cut);
    s.push_str(&format!("…[truncated {dropped} bytes]"));
    s
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn redacts_presigned_s3_url() {
        let input = "failed to GET https://bkt.s3.amazonaws.com/private-stdins/abc?X-Amz-Signature=deadbeefcafe&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE";
        let out = sanitize(input);
        assert!(!out.contains("X-Amz-Signature"), "signature leaked: {out}");
        assert!(!out.contains("deadbeefcafe"), "signature value leaked: {out}");
        assert!(
            out.contains("https://bkt.s3.amazonaws.com/private-stdins/abc?[REDACTED]"),
            "{out}"
        );
    }

    #[test]
    fn redacts_aws_access_key_id() {
        let out = sanitize("creds AKIAIOSFODNN7EXAMPLE rejected");
        assert!(out.contains("[REDACTED-AWS-KEY]"), "{out}");
        assert!(!out.contains("AKIAIOSFODNN7EXAMPLE"), "{out}");
    }

    #[test]
    fn redacts_connection_string_creds() {
        let out = sanitize("error connecting to postgres://admin:hunter2@db.internal:5432/spn");
        assert!(!out.contains("hunter2"), "password leaked: {out}");
        assert!(out.contains("postgres://[REDACTED]@db.internal:5432/spn"), "{out}");
    }

    #[test]
    fn redacts_labeled_private_key() {
        let key = "0x".to_string() + &"a".repeat(64);
        let out = sanitize(&format!("sp1_private_key={key} failed to parse"));
        assert!(!out.contains(&key), "private key leaked: {out}");
        assert!(out.contains("sp1_private_key=[REDACTED]"), "{out}");
    }

    #[test]
    fn redacts_bearer_token() {
        let out = sanitize("Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9");
        assert!(!out.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"), "bearer leaked: {out}");
    }

    #[test]
    fn preserves_request_id_hex() {
        // 64-hex (request id / vk hash) must NOT be redacted.
        let id = "b".repeat(64);
        let out = sanitize(&format!("request 0x{id} failed during proving"));
        assert!(out.contains(&id), "request id was wrongly redacted: {out}");
    }

    #[test]
    fn truncates_oversized_field() {
        let huge = "x".repeat(MESSAGE_MAX * 4);
        let t = ErrorTrace::new(ErrorSource::Cluster, ErrorKind::ClusterError, huge)
            .finalize()
            .expect("useful");
        assert!(t.message.len() <= MESSAGE_MAX + 64, "len={}", t.message.len());
        assert!(t.message.contains("truncated"), "missing marker");
    }

    #[test]
    fn total_json_cap_drops_low_priority_fields() {
        let mut t = ErrorTrace::new(ErrorSource::Cluster, ErrorKind::ClusterError, "boom");
        t.stack_trace = Some("s".repeat(STACK_TRACE_MAX));
        t.stderr_excerpt = Some("e".repeat(STDERR_EXCERPT_MAX));
        t.details = Some("d".repeat(DETAILS_MAX));
        let bytes = t.to_wire_bytes().expect("serialized");
        assert!(bytes.len() <= TOTAL_JSON_MAX, "len={}", bytes.len());
    }

    #[test]
    fn cluster_proving_failure_is_captured() {
        let extra = r#"{"proving_failure":{"task_type":3,"reason":"prove shard task failed: GPU OOM\n  caused by: cuda error 2"}}"#;
        let t = ErrorTrace::from_cluster_extra_data(Some(extra))
            .and_then(ErrorTrace::finalize)
            .expect("useful trace");
        assert_eq!(t.source, ErrorSource::Cluster);
        assert_eq!(t.kind, ErrorKind::ClusterError);
        assert_eq!(t.message, "prove shard task failed: GPU OOM");
        assert!(t.details.as_deref().unwrap().contains("cuda error 2"));
        assert_eq!(t.phase.as_deref(), Some("proving (task_type 3)"));
    }

    #[test]
    fn cluster_proving_failure_real_string_task_type_is_captured() {
        // The DEPLOYED producer serializes `task_type` as the proto enum variant
        // NAME (a string, e.g. "ProveShard"), not the integer discriminant. This
        // is the shape the helper must handle to avoid falling back to `unknown`.
        let extra = r#"{"proving_failure":{"reason":"GPU OOM","task_type":"ProveShard"}}"#;
        let t = ErrorTrace::from_cluster_extra_data(Some(extra))
            .and_then(ErrorTrace::finalize)
            .expect("useful trace");
        assert_eq!(t.source, ErrorSource::Cluster);
        assert_eq!(t.kind, ErrorKind::ClusterError);
        assert_eq!(t.message, "GPU OOM");
        assert_eq!(t.phase.as_deref(), Some("proving (task_type ProveShard)"));
    }

    #[test]
    fn cluster_execution_program_panic_is_captured() {
        // failure_cause == 1 (HaltWithNonZeroExitCode) => guest program panic.
        let extra =
            r#"{"status":2,"failure_cause":1,"cycles":123,"gas":456,"public_values_hash":[]}"#;
        let t = ErrorTrace::from_cluster_extra_data(Some(extra))
            .and_then(ErrorTrace::finalize)
            .expect("useful trace");
        assert_eq!(t.kind, ErrorKind::ProgramPanic);
        assert_eq!(t.source, ErrorSource::Program);
        assert!(t.message.contains("HaltWithNonZeroExitCode"), "{}", t.message);
        assert_eq!(t.phase.as_deref(), Some("execution"));
    }

    #[test]
    fn cluster_execution_executor_error_is_captured() {
        // failure_cause == 5 (ExceededCycleLimit) => executor error.
        let extra = r#"{"status":2,"failure_cause":5,"cycles":0,"gas":0,"public_values_hash":[]}"#;
        let t = ErrorTrace::from_cluster_extra_data(Some(extra))
            .and_then(ErrorTrace::finalize)
            .expect("useful trace");
        assert_eq!(t.kind, ErrorKind::ExecutorError);
        assert_eq!(t.source, ErrorSource::Executor);
        assert!(t.message.contains("ExceededCycleLimit"), "{}", t.message);
    }

    #[test]
    fn cluster_execution_enriched_failure_message_improves_message() {
        // An enriched producer adds a bounded `failure_message` for Err(ExecutionError)
        // execute-only failures. It improves message/details; source/kind stay.
        let extra = r#"{"status":3,"failure_cause":5,"cycles":0,"gas":0,"public_values_hash":[],"failure_message":"exceeded cycle limit of 1000000"}"#;
        let t = ErrorTrace::from_cluster_extra_data(Some(extra))
            .and_then(ErrorTrace::finalize)
            .expect("useful trace");
        assert_eq!(t.kind, ErrorKind::ExecutorError);
        assert_eq!(t.source, ErrorSource::Executor);
        assert_eq!(t.message, "exceeded cycle limit of 1000000");
        assert_eq!(t.phase.as_deref(), Some("execution"));
    }

    #[test]
    fn cluster_execution_enriched_exit_code_is_populated() {
        // An enriched producer adds `exit_code` for non-zero halt failures.
        let extra = r#"{"status":3,"failure_cause":1,"cycles":123,"gas":456,"public_values_hash":[],"exit_code":101}"#;
        let t = ErrorTrace::from_cluster_extra_data(Some(extra))
            .and_then(ErrorTrace::finalize)
            .expect("useful trace");
        assert_eq!(t.kind, ErrorKind::ProgramPanic);
        assert_eq!(t.source, ErrorSource::Program);
        assert_eq!(t.exit_code, Some(101));
    }

    #[test]
    fn cluster_execution_old_payload_unchanged_by_enrichment() {
        // Back-compat: a failure_cause-only payload (no enrichment keys) must
        // parse exactly as before — generic message, no details, no exit_code.
        let extra = r#"{"status":3,"failure_cause":5,"cycles":0,"gas":0,"public_values_hash":[]}"#;
        let t = ErrorTrace::from_cluster_extra_data(Some(extra)).expect("useful trace");
        assert_eq!(t.message, "execution failed: ExceededCycleLimit");
        assert_eq!(t.details, None);
        assert_eq!(t.exit_code, None);
    }

    #[test]
    fn cluster_execution_enriched_message_is_redacted_and_bounded() {
        // A secret smuggled into failure_message is redacted by finalize, and an
        // oversized message is bounded by MESSAGE_MAX.
        let big = "x".repeat(MESSAGE_MAX * 2);
        let extra = format!(
            r#"{{"status":3,"failure_cause":5,"failure_message":"boom aws_secret_access_key=AKIAEXAMPLE12345 {big}"}}"#
        );
        let t = ErrorTrace::from_cluster_extra_data(Some(&extra))
            .and_then(ErrorTrace::finalize)
            .expect("useful trace");
        assert!(!t.message.contains("AKIAEXAMPLE12345"), "secret not redacted: {}", t.message);
        assert!(t.message.contains(REDACTED));
        // Bounded near MESSAGE_MAX (truncate_bytes appends a short marker suffix).
        assert!(t.message.contains("[truncated"), "not truncated: {}", t.message.len());
        assert!(t.message.len() < MESSAGE_MAX + 64, "message not bounded: {}", t.message.len());
    }

    #[test]
    fn cluster_execution_unspecified_cause_with_message_is_kept() {
        // failure_cause == 0 (Unspecified) but the producer attached a message for an
        // unmapped Err(ExecutionError): surface it as an execution-phase executor error
        // instead of dropping it.
        let extra = r#"{"status":3,"failure_cause":0,"failure_message":"invalid memory access for untrusted program at address 1234"}"#;
        let t = ErrorTrace::from_cluster_extra_data(Some(extra))
            .and_then(ErrorTrace::finalize)
            .expect("useful trace");
        assert_eq!(t.kind, ErrorKind::ExecutorError);
        assert_eq!(t.source, ErrorSource::Executor);
        assert_eq!(t.message, "invalid memory access for untrusted program at address 1234");
        assert_eq!(t.phase.as_deref(), Some("execution"));
    }

    #[test]
    fn cluster_execution_unspecified_cause_without_message_is_none() {
        // failure_cause == 0 and no message: unchanged enum-only behavior => no trace.
        let extra = r#"{"status":3,"failure_cause":0,"cycles":0,"gas":0,"public_values_hash":[]}"#;
        assert!(ErrorTrace::from_cluster_extra_data(Some(extra)).is_none());
    }

    #[test]
    fn cluster_execution_unspecified_cause_blank_message_is_none() {
        // failure_cause == 0 with a blank/whitespace message: no useful signal.
        let extra = r#"{"status":3,"failure_cause":0,"failure_message":"   "}"#;
        assert!(ErrorTrace::from_cluster_extra_data(Some(extra)).is_none());
    }

    #[test]
    fn cluster_execution_enriched_useless_message_falls_back_to_cause() {
        // A blank failure_message must not blank the trace: the cause-derived
        // message survives.
        let extra = r#"{"status":3,"failure_cause":5,"failure_message":"   "}"#;
        let t = ErrorTrace::from_cluster_extra_data(Some(extra)).expect("useful trace");
        assert_eq!(t.message, "execution failed: ExceededCycleLimit");
    }

    #[test]
    fn execute_failure_cause_builder() {
        // The SPN executor builds traces straight from the typed enum code.
        let panic = ErrorTrace::from_execute_failure_cause(1).expect("halt => panic");
        assert_eq!(panic.kind, ErrorKind::ProgramPanic);
        assert_eq!(panic.source, ErrorSource::Program);
        assert!(panic.message.contains("HaltWithNonZeroExitCode"));
        assert_eq!(panic.phase.as_deref(), Some("execution"));

        let exec = ErrorTrace::from_execute_failure_cause(9).expect("gas => executor error");
        assert_eq!(exec.kind, ErrorKind::ExecutorError);
        assert!(exec.message.contains("ExceededGasLimit"));

        // Unspecified/zero carries no useful signal.
        assert!(ErrorTrace::from_execute_failure_cause(0).is_none());
    }

    #[test]
    fn successful_execution_result_yields_no_trace() {
        let extra =
            r#"{"status":1,"failure_cause":0,"cycles":10,"gas":20,"public_values_hash":[1,2,3]}"#;
        assert!(ErrorTrace::from_cluster_extra_data(Some(extra)).is_none());
    }

    #[test]
    fn empty_extra_data_yields_no_trace() {
        assert!(ErrorTrace::from_cluster_extra_data(None).is_none());
        assert!(ErrorTrace::from_cluster_extra_data(Some("")).is_none());
        assert!(ErrorTrace::from_cluster_extra_data(Some("{}")).is_none());
    }

    #[test]
    fn bare_unknown_error_is_omitted() {
        let t =
            ErrorTrace::new(ErrorSource::Unknown, ErrorKind::Unknown, "Unknown Error").finalize();
        assert!(t.is_none(), "bare unknown error should be omitted as junk");
    }

    #[test]
    fn unknown_message_with_details_is_kept() {
        let mut t = ErrorTrace::new(ErrorSource::Cluster, ErrorKind::Unknown, "Unknown Error");
        t.details = Some("worker 7 dropped connection mid-proof".to_string());
        let t = t.finalize().expect("kept because it has details");
        assert!(t.details.is_some());
    }

    #[test]
    fn bridge_panic_extracts_location() {
        let err = "task panicked\nPanic details:\npanic occurred at sp1-core/src/foo.rs:42:7: index out of bounds: the len is 3 but the index is 9";
        let t = ErrorTrace::from_bridge_error(err).finalize().expect("useful");
        assert_eq!(t.source, ErrorSource::Bridge);
        assert_eq!(t.kind, ErrorKind::ProgramPanic);
        let panic = t.panic.expect("panic info");
        assert_eq!(panic.location.as_deref(), Some("sp1-core/src/foo.rs:42:7"));
        assert!(panic.message.contains("index out of bounds"));
    }

    #[test]
    fn bridge_plain_error_has_no_panic() {
        let t = ErrorTrace::from_bridge_error("failed to download program: timeout")
            .finalize()
            .expect("useful");
        assert!(t.panic.is_none());
        assert_eq!(t.kind, ErrorKind::ExecutorError);
    }

    #[test]
    fn wire_roundtrip_and_ingestion() {
        let t = ErrorTrace::from_cluster_extra_data(Some(
            r#"{"proving_failure":{"task_type":1,"reason":"boom"}}"#,
        ))
        .and_then(ErrorTrace::finalize)
        .unwrap();
        let bytes = t.to_wire_bytes().unwrap();
        let value = sanitize_wire_trace(&bytes).expect("valid ingestion");
        assert_eq!(value.get("message").and_then(|v| v.as_str()), Some("boom"));
        assert_eq!(value.get("version").and_then(|v| v.as_u64()), Some(1));
    }

    #[test]
    fn ingestion_rejects_junk_and_oversized() {
        assert!(sanitize_wire_trace(b"").is_none());
        assert!(sanitize_wire_trace(b"not json").is_none());
        assert!(sanitize_wire_trace(b"\"just a string\"").is_none());
        assert!(sanitize_wire_trace(b"{}").is_none());
        let oversized = vec![b'a'; WIRE_BYTES_MAX + 1];
        assert!(sanitize_wire_trace(&oversized).is_none());
    }

    #[test]
    fn strips_ansi_color_codes() {
        let out = sanitize("\x1b[31merror\x1b[0m: boom");
        assert_eq!(out, "error: boom");
    }

    #[test]
    fn strips_std_backtrace_frames() {
        let stack = "  0: rust_begin_unwind\n  1: core::panicking::panic_fmt\n  2: spn_prover::prove::execute\n  3: std::rt::lang_start";
        let stripped = strip_stack_boilerplate(stack);
        assert!(stripped.contains("spn_prover::prove::execute"), "{stripped}");
        assert!(!stripped.contains("panic_fmt"), "{stripped}");
        assert!(!stripped.contains("rust_begin_unwind"), "{stripped}");
    }

    #[test]
    fn backward_compat_deserialize_without_optional_fields() {
        // An older/minimal payload (only required fields) must still deserialize.
        let json = r#"{"version":1,"source":"cluster","kind":"cluster_error","message":"boom"}"#;
        let t: ErrorTrace = serde_json::from_str(json).expect("deserializes");
        assert_eq!(t.message, "boom");
        assert!(t.details.is_none());
        assert!(t.panic.is_none());
    }

    // --- Hardening tests added after adversarial review ---

    #[test]
    fn redacts_presigned_url_wrapped_in_punctuation() {
        // reqwest renders transport errors as `... (https://...?X-Amz-...)`, so the
        // URL token starts with '(' — the signature must STILL be redacted.
        let input = "error sending request for url (https://bkt.s3.amazonaws.com/x?X-Amz-Signature=SIGVALUE&X-Amz-Credential=CRED)";
        let out = sanitize(input);
        assert!(!out.contains("SIGVALUE"), "signature leaked: {out}");
        assert!(!out.contains("X-Amz-Signature"), "signature param leaked: {out}");
        assert!(out.contains("(https://bkt.s3.amazonaws.com/x?[REDACTED]"), "{out}");
    }

    #[test]
    fn redacts_aws_key_with_surrounding_punctuation() {
        for input in [
            "AKIAIOSFODNN7EXAMPLE,",
            "(AKIAIOSFODNN7EXAMPLE)",
            "\"AKIAIOSFODNN7EXAMPLE\"",
            "creds:AKIAIOSFODNN7EXAMPLE",
            "s3://bucket/AKIAIOSFODNN7EXAMPLE/file",
        ] {
            let out = sanitize(input);
            assert!(!out.contains("AKIAIOSFODNN7EXAMPLE"), "aws key leaked from {input:?}: {out}");
            assert!(out.contains("[REDACTED-AWS-KEY]"), "no redaction marker for {input:?}: {out}");
        }
    }

    #[test]
    fn redacts_colon_secret_with_slash_value() {
        // base64/JWT secrets contain '/', which previously bypassed the colon rule.
        let out = sanitize("api_key:ab/cd/ef token:eyJ/abc.def");
        assert!(!out.contains("ab/cd/ef"), "api_key leaked: {out}");
        assert!(!out.contains("eyJ/abc.def"), "token leaked: {out}");
    }

    #[test]
    fn preserves_file_line_col() {
        // file:line:col must NOT be redacted (numeric value => not a secret).
        let out = sanitize("at src/foo.rs:42:7 something broke");
        assert!(out.contains("src/foo.rs:42:7"), "file:line wrongly redacted: {out}");
    }

    #[test]
    fn redacts_space_separated_secret() {
        for input in ["password = hunter2", "password: hunter2", "api_key = sk-abc123"] {
            let out = sanitize(input);
            assert!(
                !out.contains("hunter2") && !out.contains("sk-abc123"),
                "leaked: {input:?} -> {out}"
            );
            assert!(out.contains(REDACTED), "no redaction for {input:?}: {out}");
        }
    }

    #[test]
    fn prose_mentioning_password_is_not_over_redacted() {
        // A bare sensitive word not followed by an assignment must not eat the next word.
        let out = sanitize("the password was rejected by the server");
        assert!(out.contains("was rejected by the server"), "over-redacted prose: {out}");
    }

    #[test]
    fn id_fields_are_sanitized_and_bounded() {
        let huge = "x".repeat(ID_FIELD_MAX * 4);
        let mut t = ErrorTrace::new(ErrorSource::Cluster, ErrorKind::ClusterError, "boom")
            .with_request_id("password=hunter2");
        t.job_id = Some(huge);
        let t = t.finalize().expect("useful");
        // Secret in an id field is redacted...
        assert_eq!(t.request_id.as_deref(), Some("password=[REDACTED]"));
        // ...and oversized id fields are bounded.
        assert!(t.job_id.as_ref().unwrap().len() <= ID_FIELD_MAX + 32, "job_id not bounded");
    }

    #[test]
    fn total_size_holds_even_with_huge_id_fields() {
        // Previously id/timestamp fields bypassed all caps, allowing ~60KB JSONB.
        let big = "z".repeat(50 * 1024);
        let mut t = ErrorTrace::new(ErrorSource::Cluster, ErrorKind::ClusterError, "boom")
            .with_request_id(big.clone());
        t.job_id = Some(big.clone());
        t.cluster_id = Some(big.clone());
        t.timestamp = Some(big);
        let t = t.finalize().expect("useful");
        let bytes = t.to_wire_bytes().expect("serialized");
        assert!(bytes.len() <= TOTAL_JSON_MAX, "total size not bounded: {}", bytes.len());
    }

    #[test]
    fn total_json_cap_preserves_priority_order() {
        let mut t = ErrorTrace::new(ErrorSource::Cluster, ErrorKind::ClusterError, "real message");
        t.stack_trace = Some("s".repeat(STACK_TRACE_MAX));
        t.stderr_excerpt = Some("e".repeat(STDERR_EXCERPT_MAX));
        t.details = Some("d".repeat(DETAILS_MAX));
        let bytes = t.to_wire_bytes().expect("serialized");
        let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
        // message is never dropped; stack_trace is dropped first.
        assert_eq!(value.get("message").and_then(|v| v.as_str()), Some("real message"));
        assert!(value.get("stack_trace").is_none(), "stack_trace should be dropped first");
    }

    #[test]
    fn tighter_is_useful_drops_short_junk() {
        for junk in ["failed", "panic", "x", "1", "??", "error:", "Some(Error)"] {
            assert!(
                ErrorTrace::new(ErrorSource::Unknown, ErrorKind::Unknown, junk)
                    .finalize()
                    .is_none(),
                "junk message {junk:?} should be dropped"
            );
        }
        // A short-but-real message with a signal field is kept.
        let mut t = ErrorTrace::new(ErrorSource::Executor, ErrorKind::ExecutorError, "OOM");
        t.exit_code = Some(137);
        assert!(t.finalize().is_some(), "real short message with exit_code should be kept");
    }

    #[test]
    fn bridge_panic_two_line_panicked_at_form() {
        // The real producer (Rust >= 1.65) emits the std two-line panic Display
        // `panicked at {loc}:\n{payload}`, optionally wrapped by ErrorCapture.
        let err = "proving task failed\nPanic details:\npanic occurred at node/src/x.rs:10:5: panicked at node/src/x.rs:10:5:\nattempt to subtract with overflow";
        let t = ErrorTrace::from_bridge_error(err).finalize().expect("useful");
        assert_eq!(t.kind, ErrorKind::ProgramPanic);
        let p = t.panic.expect("panic info");
        assert_eq!(p.location.as_deref(), Some("node/src/x.rs:10:5"));
        assert!(
            p.message.contains("attempt to subtract with overflow"),
            "real panic payload dropped: msg={}",
            p.message
        );
    }

    #[test]
    fn bridge_bare_payload_is_kept_as_message() {
        // When the panic hook didn't capture a location, the bridge passes just the
        // payload; it's still kept (as the message) rather than lost.
        let t =
            ErrorTrace::from_bridge_error("index out of bounds: the len is 3 but the index is 9")
                .finalize()
                .expect("useful");
        assert!(t.message.contains("index out of bounds"));
    }

    #[test]
    fn cluster_unknown_shape_extra_data_is_kept() {
        // An extra_data shape that is neither proving_failure nor execution_result
        // is kept best-effort (not silently dropped).
        let t = ErrorTrace::from_cluster_extra_data(Some(r#"{"weird":"worker 7 died mid-proof"}"#))
            .and_then(ErrorTrace::finalize)
            .expect("kept best-effort");
        assert_eq!(t.source, ErrorSource::Cluster);
        assert_eq!(t.kind, ErrorKind::Unknown);
        assert!(t.message.contains("worker 7 died") || t.details.is_some(), "msg={}", t.message);
    }

    #[test]
    fn ingestion_rejects_non_utf8_and_json_array() {
        assert!(sanitize_wire_trace(&[0xff, 0xfe, 0x00, 0x80]).is_none());
        assert!(sanitize_wire_trace(b"[1,2,3]").is_none());
    }

    #[test]
    fn ingestion_redacts_secrets_in_raw_producer_json() {
        // A malicious/buggy producer that sends raw, UNsanitized canonical JSON
        // must still have its secrets redacted at RPC ingress.
        let raw = br#"{"version":1,"source":"cluster","kind":"cluster_error",
            "message":"connect postgres://admin:hunter2@db:5432/spn failed",
            "details":"key sp1_private_key=0xdeadbeef and AKIAIOSFODNN7EXAMPLE"}"#;
        let v = sanitize_wire_trace(raw).expect("kept after sanitizing");
        let s = v.to_string();
        assert!(!s.contains("hunter2"), "conn-string password leaked: {s}");
        assert!(!s.contains("0xdeadbeef"), "private key leaked: {s}");
        assert!(!s.contains("AKIAIOSFODNN7EXAMPLE"), "aws key leaked: {s}");
    }

    #[test]
    fn ingestion_drops_unknown_schema_fields() {
        // Fields outside the canonical schema are dropped, not stored verbatim.
        let raw = br#"{"version":1,"source":"cluster","kind":"cluster_error",
            "message":"boom","evil_blob":"AKIAIOSFODNN7EXAMPLE secret data"}"#;
        let v = sanitize_wire_trace(raw).expect("kept");
        assert!(v.get("evil_blob").is_none(), "unknown field stored: {v}");
        assert!(v.get("message").is_some());
        assert!(
            !v.to_string().contains("AKIAIOSFODNN7EXAMPLE"),
            "secret survived in unknown field"
        );
    }

    #[test]
    fn ingestion_drops_useless_unknown_error_object() {
        // A well-formed object whose only content is "Unknown Error" is dropped.
        let raw = br#"{"version":1,"source":"unknown","kind":"unknown","message":"Unknown Error"}"#;
        assert!(sanitize_wire_trace(raw).is_none());
        // And a plain empty object is dropped (missing required fields).
        assert!(sanitize_wire_trace(b"{}").is_none());
    }

    #[test]
    fn ingestion_bounds_oversized_canonical_json() {
        // A schema-valid object with a giant message is bounded, not stored at 60KB.
        let big = "x".repeat(60 * 1024);
        let raw = format!(
            r#"{{"version":1,"source":"cluster","kind":"cluster_error","message":"{big}"}}"#
        );
        // Under WIRE_BYTES_MAX (64KB) so it passes the length gate, then finalize
        // truncates the message field.
        let v = sanitize_wire_trace(raw.as_bytes()).expect("kept but bounded");
        let stored_len = v.to_string().len();
        assert!(stored_len <= TOTAL_JSON_MAX, "stored {stored_len} bytes exceeds cap");
    }

    #[test]
    fn redacts_auth_credentials_split_across_tokens() {
        // The label token carries the scheme word and the real credential is the
        // next token — across schemes, header casing, and the JSON shape that
        // `format!("{err:#}")` chains routinely produce.
        for (input, secret) in [
            (r#"{"authorization":"Bearer eyJhbGSECRETvalue"}"#, "eyJhbGSECRETvalue"),
            ("Authorization:Bearer eyJhbGSECRETvalue", "eyJhbGSECRETvalue"),
            ("Authorization: Bearer eyJhbGSECRETvalue", "eyJhbGSECRETvalue"),
            ("Authorization: Basic dXNlcjpwYXNzd29yZA==", "dXNlcjpwYXNzd29yZA=="),
            ("Authorization: Digest SECRETDIGEST", "SECRETDIGEST"),
            ("x-api-key: SECRETKEYVAL", "SECRETKEYVAL"),
            ("Cookie: session=SECRETSESSION", "SECRETSESSION"),
        ] {
            let out = sanitize(input);
            assert!(!out.contains(secret), "credential leaked from {input:?}: {out}");
        }
        // And a presigned URL embedded in a JSON error string is still redacted.
        let json = r#"{"err":"GET https://b.s3.amazonaws.com/k?X-Amz-Signature=LEAK failed"}"#;
        let out = sanitize(json);
        assert!(!out.contains("LEAK"), "presigned sig leaked in json: {out}");
    }

    #[test]
    fn redacts_all_pairs_in_multi_value_cookie() {
        // A Cookie header carries multiple name=value pairs; later pairs whose
        // names aren't individually sensitive must not leak.
        let out = sanitize("Cookie: session=ABC; csrf=SECRET2 next=ok");
        assert!(!out.contains("SECRET2"), "later cookie pair leaked: {out}");
        assert!(!out.contains("ABC"), "first cookie pair leaked: {out}");
        // The carry-over stops at the first non-kv token; unrelated trailing prose
        // is not over-redacted.
        let out2 = sanitize("Authorization: Bearer TOK and the server failed");
        assert!(!out2.contains("TOK"), "bearer leaked: {out2}");
        assert!(out2.contains("and the server failed"), "over-redacted trailing prose: {out2}");
    }
}
