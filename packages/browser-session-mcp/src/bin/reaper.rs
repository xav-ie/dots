//! browser-session-reaper — close idle Chrome BrowserContexts.
//!
//! Reads the state file written by browser-session-mcp on each tool call,
//! connects to Chrome, and disposes any context whose `lastUsedAt` is older
//! than MAX_IDLE_HOURS. Prunes the state file afterwards.
//!
//! Usage: invoked from a NixOS systemd timer (every 12h by default).
//!
//! Environment:
//!   BROWSER_URL       (default: http://127.0.0.1:9222)
//!   STATE_FILE        (default: /var/lib/browser-session-mcp/state.json)
//!   MAX_IDLE_HOURS    (default: 24)

use anyhow::{Context, Result, anyhow};
use chromiumoxide::cdp::browser_protocol::{
    browser::BrowserContextId, target::GetBrowserContextsParams,
};
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

use browser_session_mcp::chrome;
use browser_session_mcp::logs::{LogWriter, default_logs_dir};
use browser_session_mcp::state::{default_state_file, read_state_file, write_state_file};

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();
    let browser_url =
        std::env::var("BROWSER_URL").unwrap_or_else(|_| "http://127.0.0.1:9222".to_string());
    let state_file = default_state_file();
    let max_idle_hours: f64 = std::env::var("MAX_IDLE_HOURS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(24.0);
    if !max_idle_hours.is_finite() || max_idle_hours <= 0.0 {
        return Err(anyhow!("invalid MAX_IDLE_HOURS: {max_idle_hours}"));
    }

    let mut sessions = read_state_file(&state_file)
        .await
        .with_context(|| format!("reading {}", state_file.display()))?;

    let now = OffsetDateTime::now_utc();
    let cutoff_secs = (max_idle_hours * 3600.0) as i64;

    let stale: Vec<String> = sessions
        .iter()
        .filter(|(_, rec)| {
            let Ok(t) = OffsetDateTime::parse(&rec.last_used_at, &Rfc3339) else {
                return false;
            };
            (now - t).whole_seconds() > cutoff_secs
        })
        .map(|(id, _)| id.clone())
        .collect();

    if stale.is_empty() {
        println!("No idle sessions to reap.");
        return Ok(());
    }

    println!(
        "Found {} idle session(s); connecting to Chrome…",
        stale.len()
    );

    let (browser, _handler) = chrome::connect(&browser_url).await?;
    let existing = browser
        .execute(GetBrowserContextsParams::default())
        .await
        .context("Target.getBrowserContexts")?;
    let existing_ids: std::collections::HashSet<String> = existing
        .result
        .browser_context_ids
        .iter()
        .map(|c| c.inner().to_string())
        .collect();

    let writer = LogWriter::new(default_logs_dir());
    let mut reaped = 0usize;
    let mut already_gone = 0usize;

    for session_id in &stale {
        if !existing_ids.contains(session_id) {
            already_gone += 1;
            sessions.remove(session_id);
            let _ = writer.close_session(session_id).await;
            continue;
        }
        match browser
            .dispose_browser_context(BrowserContextId::new(session_id))
            .await
        {
            Ok(_) => {
                sessions.remove(session_id);
                let _ = writer.close_session(session_id).await;
                reaped += 1;
                println!("Reaped {session_id}");
            }
            Err(err) => {
                eprintln!("Failed to close {session_id}: {err}");
            }
        }
    }

    write_state_file(&state_file, &sessions)
        .await
        .with_context(|| format!("writing {}", state_file.display()))?;
    println!(
        "Done. reaped={reaped} already-gone={already_gone} remaining={}",
        sessions.len()
    );
    Ok(())
}

fn init_tracing() {
    let filter = EnvFilter::try_from_env("RUST_LOG")
        .unwrap_or_else(|_| EnvFilter::new("browser_session_reaper=info,rmcp=warn"));
    tracing_subscriber::registry()
        .with(filter)
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(std::io::stderr)
                .with_target(false),
        )
        .init();
}
