//! browser-session-takeover — serve the human-takeover page.
//!
//! A tiny host-side HTTP daemon (systemd unit) that hands a human a live view
//! of a session's active page so they can complete a login/passkey themselves —
//! the agent never sees the credentials. See `takeover` module for the full
//! flow. All CDP traffic is browser↔Chrome; this daemon only serves the page
//! and accepts the "Done" signal.
//!
//! Environment:
//!   TAKEOVER_BIND     (default: 127.0.0.1:9223)
//!   TAKEOVER_DIR      (default: /var/lib/browser-session-mcp/takeover)
//!   CHROME_WS_BASE    (required: e.g. wss://chrome.lalala.casa)

use anyhow::Result;
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

use browser_session_mcp::takeover;

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();
    takeover::run().await
}

fn init_tracing() {
    let filter = EnvFilter::try_from_env("RUST_LOG")
        .unwrap_or_else(|_| EnvFilter::new("browser_session_mcp=info"));
    tracing_subscriber::registry()
        .with(filter)
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(std::io::stderr)
                .with_target(false),
        )
        .init();
}
