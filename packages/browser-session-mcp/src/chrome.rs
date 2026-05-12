//! Connection helpers for the persistent Chrome instance.
//!
//! We don't pass `browser_url` directly to chromiumoxide because Chrome's
//! `/json/version` returns whatever `webSocketDebuggerUrl` the browser
//! reports — typically `ws://127.0.0.1:9222/...`. When this binary runs in a
//! container or behind a proxy, that 127.0.0.1 is the wrong loopback. We fetch
//! `/json/version` ourselves, keep only the path of the reported URL, and
//! rebuild it on the externally-reachable host we already have.
use anyhow::{Context, Result, anyhow};
use chromiumoxide::Browser;
use futures::StreamExt;
use serde::Deserialize;
use tokio::task::JoinHandle;
use url::Url;

#[derive(Deserialize)]
struct VersionResponse {
    #[serde(rename = "webSocketDebuggerUrl")]
    web_socket_debugger_url: Option<String>,
}

pub async fn resolve_ws_endpoint(browser_url: &str) -> Result<String> {
    let version_url = Url::parse(browser_url)
        .with_context(|| format!("parsing BROWSER_URL {browser_url}"))?
        .join("/json/version")
        .context("building /json/version URL")?;
    let res = reqwest::get(version_url.as_str())
        .await
        .with_context(|| format!("GET {version_url}"))?;
    if !res.status().is_success() {
        return Err(anyhow!(
            "GET {version_url} returned {} {}",
            res.status().as_u16(),
            res.status().canonical_reason().unwrap_or("")
        ));
    }
    let json: VersionResponse = res
        .json()
        .await
        .with_context(|| format!("decoding /json/version body from {version_url}"))?;
    let reported = json
        .web_socket_debugger_url
        .ok_or_else(|| anyhow!("{version_url} response missing webSocketDebuggerUrl"))?;
    let reported_url = Url::parse(&reported)
        .with_context(|| format!("parsing reported webSocketDebuggerUrl {reported}"))?;

    let mut ws = version_url;
    let scheme = if ws.scheme() == "https" { "wss" } else { "ws" };
    ws.set_scheme(scheme)
        .map_err(|_| anyhow!("failed to switch scheme on {ws}"))?;
    ws.set_path(reported_url.path());
    ws.set_query(reported_url.query());
    Ok(ws.to_string())
}

/// Connect to Chrome and spawn the chromiumoxide event-loop handler. The
/// returned `JoinHandle` should be kept alive for the lifetime of `Browser`;
/// dropping it cancels the task and stops the connection.
pub async fn connect(browser_url: &str) -> Result<(Browser, JoinHandle<()>)> {
    let ws = resolve_ws_endpoint(browser_url).await?;
    let (browser, mut handler) = Browser::connect(ws.clone())
        .await
        .with_context(|| format!("connecting to {ws}"))?;
    let task = tokio::spawn(async move {
        while let Some(event) = handler.next().await {
            if let Err(err) = event {
                tracing::debug!(error = %err, "chromiumoxide handler event error");
            }
        }
    });
    Ok((browser, task))
}
