//! browser-session-mcp — MCP server over stdio.
//!
//! Connects (lazily) to a persistent Chrome via the DevTools Protocol and
//! hands out isolated BrowserContexts per caller-managed sessionId.
//!
//! Required env: BROWSER_URL (e.g. http://localhost:9222).
//! Optional env: STATE_FILE, LOGS_DIR, STATES_DIR.

use anyhow::{Context, Result};
use rmcp::ServiceExt;
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

use browser_session_mcp::chrome_ctx::ChromeContext;
use browser_session_mcp::logs::default_logs_dir;
use browser_session_mcp::saved_states::{SavedStateStore, default_states_dir};
use browser_session_mcp::server::BrowserSessionServer;
use browser_session_mcp::state::{StateStore, default_state_file};

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();

    let browser_url = match std::env::var("BROWSER_URL") {
        Ok(v) if !v.is_empty() => v,
        _ => {
            eprintln!("BROWSER_URL is required.");
            std::process::exit(1);
        }
    };
    let state = StateStore::load(default_state_file())
        .await
        .context("loading state store")?;
    let ctx = ChromeContext::new(browser_url, state.clone());
    let saved_states = SavedStateStore::new(default_states_dir());
    let logs_dir = default_logs_dir();
    let srv = BrowserSessionServer::new(ctx, logs_dir, saved_states);

    tracing::info!("browser-session-mcp starting");

    let svc = srv
        .serve((tokio::io::stdin(), tokio::io::stdout()))
        .await
        .context("starting stdio service")?;
    let _ = svc.waiting().await;
    if let Err(err) = state.flush_now().await {
        tracing::warn!(error = %err, "final state flush failed");
    }
    Ok(())
}

fn init_tracing() {
    let filter = EnvFilter::try_from_env("RUST_LOG")
        .unwrap_or_else(|_| EnvFilter::new("browser_session_mcp=info,rmcp=warn"));
    tracing_subscriber::registry()
        .with(filter)
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(std::io::stderr)
                .with_target(false),
        )
        .init();
}
