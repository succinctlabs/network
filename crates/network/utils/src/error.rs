use std::{error::Error, panic};

/// A helper struct to handle panic and error capturing.
pub struct ErrorCapture {
    rx: std::sync::mpsc::Receiver<String>,
}

impl ErrorCapture {
    /// Creates a new error capture instance.
    #[must_use]
    pub fn new() -> Self {
        let (tx, rx) = std::sync::mpsc::channel();
        let tx_clone = tx;

        // Set up the new hook that captures panic messages
        panic::set_hook(Box::new(move |panic_info| {
            if let Some(location) = panic_info.location() {
                let msg = format!("panic occurred at {location}: {panic_info}");
                let _ = tx_clone.send(msg);
            }
        }));

        Self { rx }
    }

    /// Collects any panic messages that were captured.
    fn collect_messages(&self) -> Vec<String> {
        let mut messages = Vec::new();
        while let Ok(msg) = self.rx.try_recv() {
            messages.push(msg);
        }
        messages
    }

    /// Formats an error with any captured panic messages.
    pub fn format_error(&self, error: impl std::fmt::Display) -> String {
        let messages = self.collect_messages();
        if messages.is_empty() {
            format!("{error}")
        } else {
            format!("{error}\nPanic details:\n{}", messages.join("\n"))
        }
    }

    /// Extracts a readable message from a panic payload.
    #[must_use]
    pub fn extract_panic_message(panic_err: &Box<dyn std::any::Any + Send>) -> String {
        if let Some(s) = panic_err.downcast_ref::<&str>() {
            (*s).to_string()
        } else if let Some(s) = panic_err.downcast_ref::<String>() {
            s.clone()
        } else if let Some(e) = panic_err.downcast_ref::<Box<dyn Error + Send>>() {
            e.to_string()
        } else if let Some(e) = panic_err.downcast_ref::<anyhow::Error>() {
            format!("{e:#}")
        } else {
            format!("{panic_err:?}")
        }
    }
}

impl Default for ErrorCapture {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for ErrorCapture {
    fn drop(&mut self) {
        // Remove the current hook and set a basic default one
        let _ = panic::take_hook();
        panic::set_hook(Box::new(|info| {
            eprintln!("{info}");
        }));
    }
}
