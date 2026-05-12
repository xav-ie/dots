//! browser-session-listener — long-running CDP attach + per-visit NDJSON log.
//!
//! Decoupled from the MCP subprocess on purpose: lifecycle is tied to
//! chrome-headless via a systemd service with Restart=always. Console +
//! network events captured here survive any number of mcp-proxy churns.
//!
//! Layout:
//!   <LOGS_DIR>/<sessionId>/<padded-seq>-<targetId>.ndjson
//!
//! Top-level navigation (Page.frameNavigated on the main frame) opens a fresh
//! visit file. The Document-level request that triggered the nav fires
//! *before* frameNavigated, so we retroactively bump its seq when nav fires.
use anyhow::{Context, Result};
use chromiumoxide::Page;
use chromiumoxide::cdp::browser_protocol::{
    network::{
        EnableParams as NetworkEnableParams, EventLoadingFailed, EventLoadingFinished,
        EventRequestWillBeSent, EventResponseReceived, ResourceType,
    },
    page::{EnableParams as PageEnableParams, EventFrameNavigated, NavigationType},
    target::TargetId,
};
use chromiumoxide::cdp::js_protocol::runtime::{
    EnableParams as RuntimeEnableParams, EventConsoleApiCalled, EventExceptionThrown,
};
use futures::StreamExt;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::Duration;
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use tokio::sync::Mutex;
use tracing_subscriber::{EnvFilter, layer::SubscriberExt, util::SubscriberInitExt};

use browser_session_mcp::chrome;
use browser_session_mcp::logs::{ConsoleEntry, LogWriter, NetworkEntry, default_logs_dir};

const RECONNECT_BACKOFF: Duration = Duration::from_secs(2);

#[tokio::main]
async fn main() -> Result<()> {
    init_tracing();
    let browser_url =
        std::env::var("BROWSER_URL").unwrap_or_else(|_| "http://127.0.0.1:9222".to_string());
    let writer = LogWriter::new(default_logs_dir());

    let shutdown = tokio::signal::ctrl_c();
    tokio::pin!(shutdown);

    loop {
        let run = run_once(browser_url.clone(), writer.clone());
        tokio::pin!(run);
        tokio::select! {
            res = &mut run => match res {
                Ok(()) => tracing::info!("session ended cleanly; reconnecting"),
                Err(err) => {
                    if is_connect_err(&err) {
                        tracing::info!(error = %err, "waiting for browser");
                    } else {
                        tracing::warn!(error = %err, "session ended");
                    }
                }
            },
            _ = &mut shutdown => {
                tracing::info!("shutting down");
                return Ok(());
            }
        }
        tokio::time::sleep(RECONNECT_BACKOFF).await;
    }
}

fn init_tracing() {
    let filter = EnvFilter::try_from_env("RUST_LOG")
        .unwrap_or_else(|_| EnvFilter::new("browser_session_listener=info,rmcp=warn"));
    tracing_subscriber::registry()
        .with(filter)
        .with(
            tracing_subscriber::fmt::layer()
                .with_writer(std::io::stdout)
                .with_target(false),
        )
        .init();
}

fn is_connect_err(err: &anyhow::Error) -> bool {
    let msg = format!("{err:#}").to_lowercase();
    msg.contains("refused") || msg.contains("connect") || msg.contains("tcp")
}

async fn run_once(browser_url: String, writer: LogWriter) -> Result<()> {
    tracing::info!(url = %browser_url, "connecting");
    let (mut browser, mut handler_task) = chrome::connect(&browser_url).await?;
    tracing::info!("connected; discovering existing targets");

    // By default chromiumoxide only knows about targets attached AFTER our
    // connect. Pull in pre-existing ones so a listener restart still captures
    // events from already-open contexts.
    browser.fetch_targets().await.context("Target.getTargets")?;
    // The just-fetched targets aren't guaranteed to be ready yet.
    tokio::time::sleep(Duration::from_millis(200)).await;

    let wired: Arc<Mutex<HashSet<String>>> = Arc::new(Mutex::new(HashSet::new()));

    // Wire every page we know about so far.
    for page in browser.pages().await.unwrap_or_default() {
        let target_id = page.target_id().inner().to_string();
        {
            let mut g = wired.lock().await;
            if g.contains(&target_id) {
                continue;
            }
            g.insert(target_id.clone());
        }
        spawn_target_loop(page, writer.clone(), wired.clone()).await;
    }

    // Watch for new attachments.
    let mut attached = browser
        .event_listener::<chromiumoxide::cdp::browser_protocol::target::EventAttachedToTarget>()
        .await
        .context("Target.attachedToTarget")?;

    loop {
        tokio::select! {
            Some(event) = attached.next() => {
                let info = &event.target_info;
                if info.r#type != "page" { continue; }
                let target_id = info.target_id.inner().to_string();
                {
                    let mut g = wired.lock().await;
                    if g.contains(&target_id) { continue; }
                    g.insert(target_id.clone());
                }
                match browser.get_page(TargetId::new(&target_id)).await {
                    Ok(page) => spawn_target_loop(page, writer.clone(), wired.clone()).await,
                    Err(err) => tracing::warn!(target = %target_id, error = %err, "failed to attach"),
                }
            }
            _ = &mut handler_task => {
                return Ok(());
            }
        }
    }
}

#[derive(Debug, Default)]
struct InflightRequest {
    method: String,
    url: String,
    t: String,
    seq: u32,
    frame_id: Option<String>,
    resource_type: Option<ResourceType>,
    status: Option<i64>,
}

#[derive(Debug)]
struct TargetState {
    ctx_id: String,
    target_id: String,
    current_seq: u32,
    inflight: HashMap<String, InflightRequest>,
}

async fn spawn_target_loop(page: Page, writer: LogWriter, wired: Arc<Mutex<HashSet<String>>>) {
    let target_id = page.target_id().inner().to_string();
    tokio::spawn(async move {
        if let Err(err) = target_loop(page.clone(), writer).await {
            tracing::warn!(target = %target_id, error = %err, "target loop exited with error");
        }
        wired.lock().await.remove(&target_id);
    });
}

async fn target_loop(page: Page, writer: LogWriter) -> Result<()> {
    // Per-target setup: enable the three CDP domains we depend on.
    page.execute(NetworkEnableParams::default())
        .await
        .context("Network.enable")?;
    page.execute(RuntimeEnableParams::default())
        .await
        .context("Runtime.enable")?;
    page.execute(PageEnableParams::default())
        .await
        .context("Page.enable")?;

    // Figure out the BrowserContext this target belongs to. chromiumoxide
    // doesn't expose this directly, so we read it back via Target.getTargetInfo.
    let info = page
        .execute(
            chromiumoxide::cdp::browser_protocol::target::GetTargetInfoParams::builder()
                .target_id(page.target_id().clone())
                .build(),
        )
        .await
        .context("Target.getTargetInfo")?;
    let ctx_id = match info.result.target_info.browser_context_id.clone() {
        Some(c) => c.inner().to_string(),
        None => {
            // Default context — out of scope for the listener.
            return Ok(());
        }
    };
    let target_id = page.target_id().inner().to_string();

    // If the target already has a real URL (e.g. picked up from
    // fetch_targets), open an initial visit immediately. Otherwise wait for
    // the first frameNavigated.
    let initial_seq = if !info.result.target_info.url.is_empty() {
        writer
            .open_visit(&ctx_id, &target_id, &info.result.target_info.url)
            .await
            .unwrap_or(0)
    } else {
        0
    };

    let state = Arc::new(Mutex::new(TargetState {
        ctx_id: ctx_id.clone(),
        target_id: target_id.clone(),
        current_seq: initial_seq,
        inflight: HashMap::new(),
    }));

    let mut frame_navs = page.event_listener::<EventFrameNavigated>().await?;
    let mut req_sent = page.event_listener::<EventRequestWillBeSent>().await?;
    let mut resp = page.event_listener::<EventResponseReceived>().await?;
    let mut fin = page.event_listener::<EventLoadingFinished>().await?;
    let mut failed = page.event_listener::<EventLoadingFailed>().await?;
    let mut console = page.event_listener::<EventConsoleApiCalled>().await?;
    let mut excs = page.event_listener::<EventExceptionThrown>().await?;

    tracing::info!(target = %target_id, ctx = %ctx_id, seq = initial_seq, "wired");

    loop {
        tokio::select! {
            Some(e) = frame_navs.next() => {
                on_frame_navigated(&page, &writer, &state, &e).await;
            }
            Some(e) = req_sent.next() => {
                on_request_will_be_sent(&state, &e).await;
            }
            Some(e) = resp.next() => {
                on_response_received(&state, &e).await;
            }
            Some(e) = fin.next() => {
                on_loading_finished(&writer, &state, &e).await;
            }
            Some(e) = failed.next() => {
                on_loading_failed(&writer, &state, &e).await;
            }
            Some(e) = console.next() => {
                on_console(&writer, &state, &e).await;
            }
            Some(e) = excs.next() => {
                on_exception(&writer, &state, &e).await;
            }
            else => break,
        }
    }
    Ok(())
}

async fn on_frame_navigated(
    _page: &Page,
    writer: &LogWriter,
    state: &Arc<Mutex<TargetState>>,
    e: &EventFrameNavigated,
) {
    // Only top-level navigations open new visits.
    if e.frame.parent_id.is_some() {
        return;
    }
    // Skip BFCache restores; they reuse existing page state.
    if matches!(e.r#type, NavigationType::BackForwardCacheRestore) {
        return;
    }
    let url = e.frame.url.clone();
    let (ctx_id, target_id) = {
        let s = state.lock().await;
        (s.ctx_id.clone(), s.target_id.clone())
    };
    match writer.open_visit(&ctx_id, &target_id, &url).await {
        Ok(new_seq) => {
            let mut s = state.lock().await;
            let old_seq = s.current_seq;
            s.current_seq = new_seq;
            // Retroactively bump the in-flight Document request for this frame
            // — it fired before this navigation event and is tagged with the
            // previous seq.
            let frame_id = Some(e.frame.id.inner().to_string());
            for inf in s.inflight.values_mut() {
                if matches!(inf.resource_type, Some(ResourceType::Document))
                    && inf.frame_id == frame_id
                    && inf.seq == old_seq
                {
                    inf.seq = new_seq;
                }
            }
            tracing::info!(seq = new_seq, ctx = %ctx_id, url = %url, "new visit");
        }
        Err(err) => tracing::warn!(error = %err, "open_visit failed"),
    }
}

async fn on_request_will_be_sent(state: &Arc<Mutex<TargetState>>, e: &EventRequestWillBeSent) {
    let mut s = state.lock().await;
    let seq = s.current_seq;
    s.inflight.insert(
        e.request_id.inner().to_string(),
        InflightRequest {
            method: e.request.method.clone(),
            url: e.request.url.clone(),
            t: now_rfc3339(),
            seq,
            frame_id: e.frame_id.as_ref().map(|f| f.inner().to_string()),
            resource_type: e.r#type.clone(),
            status: None,
        },
    );
}

async fn on_response_received(state: &Arc<Mutex<TargetState>>, e: &EventResponseReceived) {
    let mut s = state.lock().await;
    if let Some(inf) = s.inflight.get_mut(e.request_id.inner()) {
        inf.status = Some(e.response.status);
    }
}

async fn on_loading_finished(
    writer: &LogWriter,
    state: &Arc<Mutex<TargetState>>,
    e: &EventLoadingFinished,
) {
    let inf = {
        let mut s = state.lock().await;
        s.inflight.remove(e.request_id.inner())
    };
    let Some(inf) = inf else { return };
    write_network(writer, state, inf, None).await;
}

async fn on_loading_failed(
    writer: &LogWriter,
    state: &Arc<Mutex<TargetState>>,
    e: &EventLoadingFailed,
) {
    let inf = {
        let mut s = state.lock().await;
        s.inflight.remove(e.request_id.inner())
    };
    let Some(mut inf) = inf else { return };
    inf.status = None;
    write_network(writer, state, inf, Some(e.error_text.clone())).await;
}

async fn write_network(
    writer: &LogWriter,
    state: &Arc<Mutex<TargetState>>,
    inf: InflightRequest,
    failure: Option<String>,
) {
    if inf.seq == 0 {
        return;
    }
    let (ctx_id, target_id) = {
        let s = state.lock().await;
        (s.ctx_id.clone(), s.target_id.clone())
    };
    let entry = NetworkEntry {
        t: inf.t,
        method: inf.method,
        url: inf.url,
        status: inf.status,
        failure,
    };
    if let Err(err) = writer
        .append_network(&ctx_id, inf.seq, &target_id, entry)
        .await
    {
        tracing::warn!(error = %err, "append network failed");
    }
}

async fn on_console(
    writer: &LogWriter,
    state: &Arc<Mutex<TargetState>>,
    e: &EventConsoleApiCalled,
) {
    let text = e
        .args
        .iter()
        .map(|a| {
            if let Some(v) = a.value.as_ref() {
                value_to_str(v)
            } else if let Some(d) = a.description.as_deref() {
                d.to_string()
            } else {
                String::new()
            }
        })
        .collect::<Vec<_>>()
        .join(" ");
    let (ctx_id, target_id, seq) = {
        let s = state.lock().await;
        (s.ctx_id.clone(), s.target_id.clone(), s.current_seq)
    };
    if seq == 0 {
        return;
    }
    let entry = ConsoleEntry {
        t: now_rfc3339(),
        ty: console_type_wire(&e.r#type),
        text,
    };
    if let Err(err) = writer.append_console(&ctx_id, seq, &target_id, entry).await {
        tracing::warn!(error = %err, "append console failed");
    }
}

/// Map ConsoleApiCalledType to its CDP wire string ("log", "startGroup", …)
/// via serde rather than Debug-derived names that drop camelCase.
fn console_type_wire(
    ty: &chromiumoxide::cdp::js_protocol::runtime::ConsoleApiCalledType,
) -> String {
    serde_json::to_value(ty)
        .ok()
        .and_then(|v| v.as_str().map(str::to_string))
        .unwrap_or_else(|| format!("{ty:?}").to_lowercase())
}

async fn on_exception(
    writer: &LogWriter,
    state: &Arc<Mutex<TargetState>>,
    e: &EventExceptionThrown,
) {
    let ex = &e.exception_details;
    let description = ex
        .exception
        .as_ref()
        .and_then(|r| r.description.clone())
        .unwrap_or_default();
    let text = if description.is_empty() {
        ex.text.clone()
    } else {
        format!("{} {description}", ex.text).trim().to_string()
    };
    let (ctx_id, target_id, seq) = {
        let s = state.lock().await;
        (s.ctx_id.clone(), s.target_id.clone(), s.current_seq)
    };
    if seq == 0 {
        return;
    }
    let entry = ConsoleEntry {
        t: now_rfc3339(),
        ty: "pageerror".to_string(),
        text,
    };
    if let Err(err) = writer.append_console(&ctx_id, seq, &target_id, entry).await {
        tracing::warn!(error = %err, "append console exception failed");
    }
}

fn value_to_str(v: &serde_json::Value) -> String {
    match v {
        serde_json::Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

fn now_rfc3339() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_default()
}
