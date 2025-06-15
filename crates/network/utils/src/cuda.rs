use std::process::Command;
use tracing::debug;

/// Check if CUDA is available by testing if nvidia-smi is installed and CUDA GPUs are present.
pub fn has_cuda_support() -> bool {
    // Common paths where nvidia-smi might be installed.
    let nvidia_smi_paths = ["nvidia-smi", "/usr/bin/nvidia-smi", "/usr/local/bin/nvidia-smi"];

    for path in nvidia_smi_paths {
        match Command::new(path).output() {
            Ok(output) => {
                if output.status.success() {
                    debug!("found working nvidia-smi at: {}", path);
                    return true;
                }
                debug!("nvidia-smi at {} exists but returned error status", path);
            }
            Err(e) => {
                debug!("failed to execute nvidia-smi at {}: {}", path, e);
            }
        }
    }

    debug!("no working nvidia-smi found in any standard location");

    false
}
