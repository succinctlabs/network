//! This exposes SPN's version information over prometheus.

use metrics::{describe_gauge, gauge};

/// Contains version information for the application.
#[derive(Debug, Clone)]
pub struct VersionInfo {
    /// The version of the application.
    pub version: String,
    /// The build timestamp of the application.
    pub build_timestamp: String,
    /// The cargo features enabled for the build.
    pub cargo_features: String,
    /// The Git SHA of the build.
    pub git_sha: String,
    /// The target triple for the build.
    pub target_triple: String,
    /// The build profile (e.g., debug or release).
    pub build_profile: String,
}

impl VersionInfo {
    /// This exposes SPN's version information over prometheus.
    pub fn register_version_metrics(self) {
        let labels: [(String, String); 6] = [
            ("version".to_string(), self.version),
            ("build_timestamp".to_string(), self.build_timestamp),
            ("cargo_features".to_string(), self.cargo_features),
            ("git_sha".to_string(), self.git_sha),
            ("target_triple".to_string(), self.target_triple),
            ("build_profile".to_string(), self.build_profile),
        ];
        describe_gauge!("info", "Version information for the current build".to_string());
        let _gauge = gauge!("info", &labels);
        _gauge.set(1.0);
    }
}
