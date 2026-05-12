//! rmcp `ServerHandler` impl. Defines the tool surface and dispatches each
//! tool call to the right module.
use anyhow::{Context, Result, anyhow, bail};
use base64::Engine as _;
use chromiumoxide::Page;
use chromiumoxide::cdp::browser_protocol::{
    network::CookieParam,
    page::{CaptureScreenshotFormat, NavigateParams},
    storage::{GetCookiesParams, SetCookiesParams},
};
use chromiumoxide::page::ScreenshotParams;
use once_cell::sync::Lazy;
use regex::Regex;
use rmcp::model::{
    CallToolRequestParams, CallToolResult, Content, ErrorData as McpError, Implementation,
    JsonObject, ListToolsResult, PaginatedRequestParams, ProtocolVersion, ServerCapabilities,
    ServerInfo, Tool,
};
use rmcp::service::RequestContext;
use rmcp::{RoleServer, ServerHandler};
use serde::Serialize;
use serde_json::{Map, Value, json};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use crate::chrome_ctx::ChromeContext;
use crate::logs::{self, LogKind, ReadOpts, SessionLogEntry};
use crate::saved_states::SavedStateStore;
use crate::sessions::Viewport;
use crate::snapshot;

#[derive(Clone)]
pub struct BrowserSessionServer {
    ctx: ChromeContext,
    logs_dir: PathBuf,
    saved_states: SavedStateStore,
}

impl BrowserSessionServer {
    pub fn new(ctx: ChromeContext, logs_dir: PathBuf, saved_states: SavedStateStore) -> Self {
        Self {
            ctx,
            logs_dir,
            saved_states,
        }
    }
}

impl ServerHandler for BrowserSessionServer {
    fn get_info(&self) -> ServerInfo {
        let mut info = ServerInfo::default();
        info.protocol_version = ProtocolVersion::V_2025_06_18;
        info.capabilities = ServerCapabilities::builder().enable_tools().build();
        info.server_info = Implementation::new("browser-session-mcp", env!("CARGO_PKG_VERSION"));
        info.instructions = Some(
            "Per-call isolated browser sessions against a shared persistent Chrome. Call open_browser_session to obtain a sessionId; pass it into every subsequent tool call.".into(),
        );
        info
    }

    async fn list_tools(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, McpError> {
        Ok(ListToolsResult {
            tools: tool_defs(),
            ..Default::default()
        })
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, McpError> {
        let args = request.arguments.unwrap_or_default();
        let name = request.name.as_ref();
        match self.dispatch(name, args).await {
            Ok(result) => Ok(result),
            Err(err) => {
                // Connection-died errors mean the next call should rebuild
                // the chromiumoxide handle from scratch.
                if looks_like_disconnect(&err) {
                    self.ctx.invalidate().await;
                }
                Ok(CallToolResult::error(vec![Content::text(format!(
                    "{err:#}"
                ))]))
            }
        }
    }
}

impl BrowserSessionServer {
    async fn dispatch(&self, name: &str, args: JsonObject) -> Result<CallToolResult> {
        match name {
            "open_browser_session" => self.open_session(args).await,
            "close_browser_session" => self.close_session(args).await,
            "list_browser_sessions" => self.list_sessions().await,
            "new_page" => self.new_page(args).await,
            "list_pages" => self.list_pages(args).await,
            "navigate" => self.navigate(args).await,
            "take_screenshot" => self.take_screenshot(args).await,
            "take_snapshot" => self.take_snapshot(args).await,
            "click" => self.click(args).await,
            "type" => self.type_text(args).await,
            "wait_for" => self.wait_for(args).await,
            "evaluate" => self.evaluate(args).await,
            "list_visits" => self.list_visits(args).await,
            "list_console_messages" => self.list_console_messages(args).await,
            "list_network_requests" => self.list_network_requests(args).await,
            "save_browser_state" => self.save_state(args).await,
            "load_browser_state" => self.load_state(args).await,
            "list_browser_states" => self.list_states().await,
            "delete_browser_state" => self.delete_state(args).await,
            other => bail!("unknown tool: {other}"),
        }
    }

    // --- lifecycle ---

    async fn open_session(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let viewport = optional_viewport(&args, "viewport")?;
        let use_mobile = optional_bool(&args, "useMobileUA").unwrap_or(false);
        let info = sessions.open(viewport, use_mobile).await?;
        Ok(ok_text_struct(
            format!("Opened session {}", info.session_id),
            json!(info),
        ))
    }

    async fn close_session(&self, args: JsonObject) -> Result<CallToolResult> {
        let session_id = required_str(&args, "sessionId")?.to_string();
        // Best-effort — closing an unknown sessionId is not an error.
        if let Ok(sm) = self.ctx.sessions().await {
            let _ = sm.close(&session_id).await;
        }
        let writer = logs::LogWriter::new(self.logs_dir.clone());
        let _ = writer.close_session(&session_id).await;
        Ok(ok_text(format!("Closed session {session_id}")))
    }

    async fn list_sessions(&self) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let list = sessions.list().await?;
        let body = if list.is_empty() {
            "No active sessions.".to_string()
        } else {
            list.iter()
                .map(|s| {
                    format!(
                        "- {}  pages={}  url={}",
                        s.session_id,
                        s.page_count,
                        s.active_url.as_deref().unwrap_or("(none)")
                    )
                })
                .collect::<Vec<_>>()
                .join("\n")
        };
        Ok(ok_text_struct(body, json!({ "sessions": list })))
    }

    // --- tabs ---

    async fn new_page(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let url = optional_str(&args, "url").map(str::to_string);
        let page = sessions.new_page(&session_id, url.as_deref()).await?;
        let pages = sessions.pages(&session_id).await?;
        let index = pages.len().saturating_sub(1);
        let page_url = page.url().await?.unwrap_or_default();
        Ok(ok_text_struct(
            format!("Opened tab #{index}"),
            json!({ "index": index, "url": page_url }),
        ))
    }

    async fn list_pages(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let pages = sessions.pages(&session_id).await?;
        let mut summaries: Vec<PageSummary> = Vec::with_capacity(pages.len());
        for (i, p) in pages.iter().enumerate() {
            let url = p.url().await.ok().flatten().unwrap_or_default();
            let title = p.get_title().await.ok().flatten().unwrap_or_default();
            summaries.push(PageSummary {
                index: i,
                url,
                title,
            });
        }
        let body = if summaries.is_empty() {
            "(no pages)".to_string()
        } else {
            summaries
                .iter()
                .map(|s| format!("{}: {}  \"{}\"", s.index, s.url, s.title))
                .collect::<Vec<_>>()
                .join("\n")
        };
        Ok(ok_text_struct(body, json!({ "pages": summaries })))
    }

    async fn navigate(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let url = required_str(&args, "url")?.to_string();
        let timeout_ms = optional_u64(&args, "timeout");
        let page = sessions.active_page(&session_id).await?;
        let nav = NavigateParams::builder()
            .url(url.clone())
            .build()
            .map_err(|e| anyhow!("NavigateParams: {e}"))?;
        // chromiumoxide's goto already resolves after the load event; no
        // separate wait_for_navigation needed.
        let goto_fut = page.goto(nav);
        if let Some(ms) = timeout_ms {
            tokio::time::timeout(Duration::from_millis(ms), goto_fut)
                .await
                .map_err(|_| anyhow!("navigation timed out after {ms}ms"))?
                .context("Page.navigate")?;
        } else {
            goto_fut.await.context("Page.navigate")?;
        }
        let resolved_url = page.url().await?.unwrap_or(url);
        Ok(ok_text_struct(
            format!("Navigated to {resolved_url}"),
            json!({ "url": resolved_url }),
        ))
    }

    // --- capture ---

    async fn take_screenshot(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let full_page = optional_bool(&args, "fullPage").unwrap_or(false);
        let page = sessions.active_page(&session_id).await?;
        let params = ScreenshotParams::builder()
            .format(CaptureScreenshotFormat::Png)
            .full_page(full_page)
            .build();
        let bytes = page
            .screenshot(params)
            .await
            .context("Page.captureScreenshot")?;
        let len = bytes.len();
        let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
        Ok(CallToolResult::success(vec![
            Content::text(format!("Captured {len} bytes PNG.")),
            Content::image(b64, "image/png".to_string()),
        ]))
    }

    async fn take_snapshot(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let page = sessions.active_page(&session_id).await?;
        let tree = snapshot::snapshot(&page).await?;
        Ok(ok_text(tree))
    }

    // --- interact ---

    async fn click(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let selector = required_str(&args, "selector")?.to_string();
        let timeout = optional_u64(&args, "timeout").unwrap_or(5_000);
        let page = sessions.active_page(&session_id).await?;
        wait_for_selector(&page, &selector, timeout).await?;
        page.find_element(selector.clone())
            .await
            .with_context(|| format!("locating {selector}"))?
            .click()
            .await
            .with_context(|| format!("clicking {selector}"))?;
        Ok(ok_text(format!("Clicked {selector}")))
    }

    async fn type_text(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let selector = required_str(&args, "selector")?.to_string();
        let text = required_str(&args, "text")?.to_string();
        let clear = optional_bool(&args, "clear").unwrap_or(false);
        let page = sessions.active_page(&session_id).await?;
        wait_for_selector(&page, &selector, 5_000).await?;
        let element = page
            .find_element(selector.clone())
            .await
            .with_context(|| format!("locating {selector}"))?;
        if clear {
            let _ = element
                .call_js_fn(
                    "function() { if (this.value !== undefined) this.value = ''; }",
                    false,
                )
                .await;
        }
        element.click().await.ok();
        element
            .type_str(text.as_str())
            .await
            .with_context(|| format!("typing into {selector}"))?;
        Ok(ok_text(format!(
            "Typed {} chars into {selector}",
            text.chars().count()
        )))
    }

    async fn wait_for(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let selector = optional_str(&args, "selector").map(str::to_string);
        let text = optional_str(&args, "text").map(str::to_string);
        let timeout = optional_u64(&args, "timeout").unwrap_or(10_000);
        if selector.is_none() && text.is_none() {
            bail!("wait_for requires either `selector` or `text`.");
        }
        let page = sessions.active_page(&session_id).await?;
        if let Some(s) = selector {
            wait_for_selector(&page, &s, timeout).await?;
            return Ok(ok_text(format!("Matched selector {s}")));
        }
        let needle = text.unwrap();
        let body = format!(
            "function() {{ return document.body && document.body.innerText && document.body.innerText.includes({}); }}",
            serde_json::to_string(&needle).unwrap()
        );
        wait_until(
            || async {
                let res = page.evaluate_function(body.as_str()).await?;
                Ok(res.into_value::<bool>().unwrap_or(false))
            },
            timeout,
        )
        .await?;
        Ok(ok_text(format!("Matched text \"{needle}\"")))
    }

    async fn evaluate(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let expression = required_str(&args, "expression")?.to_string();
        let page = sessions.active_page(&session_id).await?;
        // Word-bounded so `document.returnValue` etc. don't false-match.
        static RETURN_RE: Lazy<Regex> = Lazy::new(|| Regex::new(r"\breturn\b").unwrap());
        let body = if RETURN_RE.is_match(&expression) {
            expression.clone()
        } else {
            format!("return ({expression});")
        };
        let wrapped = format!("async function() {{ {body} }}");
        let result = page
            .evaluate_function(wrapped.as_str())
            .await
            .context("Runtime.callFunctionOn")?;
        let value = result.into_value::<Value>().unwrap_or(Value::Null);
        let text = serde_json::to_string_pretty(&value).unwrap_or_else(|_| value.to_string());
        Ok(ok_text_struct(text, json!({ "result": value })))
    }

    // --- per-visit logs ---

    async fn list_visits(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let _ = sessions.context_id_for(&session_id).await?;
        let visits = logs::read_visits(&self.logs_dir, &session_id).await?;
        let body = if visits.is_empty() {
            "(no visits recorded)".to_string()
        } else {
            visits
                .iter()
                .map(|v| {
                    let short = if v.target_id.len() > 8 {
                        &v.target_id[..8]
                    } else {
                        v.target_id.as_str()
                    };
                    format!("seq={}  target={short}  {}  {}", v.seq, v.opened_at, v.url)
                })
                .collect::<Vec<_>>()
                .join("\n")
        };
        Ok(ok_text_struct(body, json!({ "visits": visits })))
    }

    async fn list_console_messages(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let _ = sessions.context_id_for(&session_id).await?;
        let visit = optional_u32(&args, "visit");
        let limit = optional_usize(&args, "limit").unwrap_or(500);
        let entries = logs::read_session_logs(
            &self.logs_dir,
            &session_id,
            ReadOpts {
                kind: Some(LogKind::Console),
                limit: Some(limit),
                visit,
            },
        )
        .await?;
        let body = if entries.is_empty() {
            "(no console messages)".to_string()
        } else {
            entries
                .iter()
                .filter_map(|e| match e {
                    SessionLogEntry::Console(c) => Some(format!("[{}] {}", c.ty, c.text)),
                    _ => None,
                })
                .collect::<Vec<_>>()
                .join("\n")
        };
        let json_entries: Vec<Value> = entries
            .iter()
            .filter_map(|e| match e {
                SessionLogEntry::Console(c) => serde_json::to_value(c).ok(),
                _ => None,
            })
            .collect();
        Ok(ok_text_struct(body, json!({ "messages": json_entries })))
    }

    async fn list_network_requests(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let _ = sessions.context_id_for(&session_id).await?;
        let visit = optional_u32(&args, "visit");
        let limit = optional_usize(&args, "limit").unwrap_or(500);
        let entries = logs::read_session_logs(
            &self.logs_dir,
            &session_id,
            ReadOpts {
                kind: Some(LogKind::Network),
                limit: Some(limit),
                visit,
            },
        )
        .await?;
        let body = if entries.is_empty() {
            "(no network requests)".to_string()
        } else {
            entries
                .iter()
                .filter_map(|e| match e {
                    SessionLogEntry::Network(n) => {
                        let status = if let Some(f) = &n.failure {
                            format!("FAIL:{f}")
                        } else if let Some(s) = n.status {
                            s.to_string()
                        } else {
                            "pending".to_string()
                        };
                        Some(format!("{} {} [{status}]", n.method, n.url))
                    }
                    _ => None,
                })
                .collect::<Vec<_>>()
                .join("\n")
        };
        let json_entries: Vec<Value> = entries
            .iter()
            .filter_map(|e| match e {
                SessionLogEntry::Network(n) => serde_json::to_value(n).ok(),
                _ => None,
            })
            .collect();
        Ok(ok_text_struct(body, json!({ "requests": json_entries })))
    }

    // --- saved browser states ---

    async fn save_state(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let name = required_str(&args, "name")?.to_string();
        let ctx_id = sessions.context_id_for(&session_id).await?;
        let result = sessions
            .browser()
            .execute(
                GetCookiesParams::builder()
                    .browser_context_id(ctx_id)
                    .build(),
            )
            .await
            .context("Storage.getCookies")?;
        let cookies_json: Vec<Value> = result
            .result
            .cookies
            .clone()
            .into_iter()
            .map(|c| serde_json::to_value(&c).unwrap_or(Value::Null))
            .collect();
        let state = self.saved_states.save(&name, cookies_json.clone()).await?;
        Ok(ok_text_struct(
            format!("Saved {} cookies as \"{name}\".", state.cookies.len()),
            json!({
                "name": state.name,
                "savedAt": state.saved_at,
                "cookieCount": state.cookies.len(),
            }),
        ))
    }

    async fn load_state(&self, args: JsonObject) -> Result<CallToolResult> {
        let sessions = self.ctx.sessions().await?;
        let session_id = required_str(&args, "sessionId")?.to_string();
        let name = required_str(&args, "name")?.to_string();
        let ctx_id = sessions.context_id_for(&session_id).await?;
        let state = self.saved_states.load(&name).await?;
        if !state.cookies.is_empty() {
            // Storage.setCookies expects CookieParam; the saved cookies came
            // from Network.Cookie. Strip fields that don't exist on
            // CookieParam (session, size) and the -1.0 expires sentinel for
            // session cookies (CookieParam treats absent expires as session,
            // and some Chrome versions reject the literal -1).
            let mut params: Vec<CookieParam> = Vec::with_capacity(state.cookies.len());
            for raw in &state.cookies {
                let mut cleaned = raw.clone();
                if let Some(obj) = cleaned.as_object_mut() {
                    obj.remove("session");
                    obj.remove("size");
                    if obj.get("expires").and_then(|v| v.as_f64()) == Some(-1.0) {
                        obj.remove("expires");
                    }
                }
                match serde_json::from_value::<CookieParam>(cleaned) {
                    Ok(p) => params.push(p),
                    Err(err) => tracing::warn!(error = %err, "skipping unparseable saved cookie"),
                }
            }
            sessions
                .browser()
                .execute(
                    SetCookiesParams::builder()
                        .cookies(params)
                        .browser_context_id(ctx_id)
                        .build()
                        .map_err(|e| anyhow!("SetCookiesParams: {e}"))?,
                )
                .await
                .context("Storage.setCookies")?;
        }
        Ok(ok_text_struct(
            format!("Loaded {} cookies from \"{name}\".", state.cookies.len()),
            json!({ "name": name, "cookieCount": state.cookies.len() }),
        ))
    }

    async fn list_states(&self) -> Result<CallToolResult> {
        let list = self.saved_states.list().await?;
        let body = if list.is_empty() {
            "(no saved states)".to_string()
        } else {
            list.iter()
                .map(|s| {
                    format!(
                        "- {}  cookies={}  saved={}",
                        s.name, s.cookie_count, s.saved_at
                    )
                })
                .collect::<Vec<_>>()
                .join("\n")
        };
        Ok(ok_text_struct(body, json!({ "states": list })))
    }

    async fn delete_state(&self, args: JsonObject) -> Result<CallToolResult> {
        let name = required_str(&args, "name")?.to_string();
        let removed = self.saved_states.delete(&name).await?;
        let msg = if removed {
            format!("Deleted \"{name}\".")
        } else {
            format!("No saved state named \"{name}\".")
        };
        Ok(ok_text_struct(
            msg,
            json!({ "name": name, "removed": removed }),
        ))
    }
}

// ---- helpers --------------------------------------------------------------

#[derive(Debug, Serialize)]
struct PageSummary {
    index: usize,
    url: String,
    title: String,
}

fn ok_text(text: impl Into<String>) -> CallToolResult {
    CallToolResult::success(vec![Content::text(text.into())])
}

fn ok_text_struct(text: impl Into<String>, structured: Value) -> CallToolResult {
    let mut r = CallToolResult::success(vec![Content::text(text.into())]);
    r.structured_content = Some(structured);
    r
}

fn looks_like_disconnect(err: &anyhow::Error) -> bool {
    let msg = format!("{err:#}").to_lowercase();
    msg.contains("connection closed")
        || msg.contains("disconnected")
        || msg.contains("connection refused")
        || msg.contains("broken pipe")
        || msg.contains("websocket")
}

fn required_str<'a>(args: &'a JsonObject, field: &str) -> Result<&'a str> {
    args.get(field)
        .and_then(|v| v.as_str())
        .filter(|s| !s.is_empty())
        .ok_or_else(|| anyhow!("{field} must be a non-empty string"))
}

fn optional_str<'a>(args: &'a JsonObject, field: &str) -> Option<&'a str> {
    args.get(field).and_then(|v| v.as_str())
}

fn optional_bool(args: &JsonObject, field: &str) -> Option<bool> {
    args.get(field).and_then(|v| v.as_bool())
}

fn optional_u32(args: &JsonObject, field: &str) -> Option<u32> {
    args.get(field)
        .and_then(|v| v.as_u64())
        .and_then(|n| u32::try_from(n).ok())
}

fn optional_u64(args: &JsonObject, field: &str) -> Option<u64> {
    args.get(field).and_then(|v| v.as_u64())
}

fn optional_usize(args: &JsonObject, field: &str) -> Option<usize> {
    args.get(field)
        .and_then(|v| v.as_u64())
        .and_then(|n| usize::try_from(n).ok())
}

fn optional_viewport(args: &JsonObject, field: &str) -> Result<Option<Viewport>> {
    let Some(v) = args.get(field) else {
        return Ok(None);
    };
    let obj = v
        .as_object()
        .ok_or_else(|| anyhow!("{field} must be an object {{width, height}}"))?;
    let width = obj
        .get("width")
        .and_then(|v| v.as_i64())
        .filter(|n| *n > 0)
        .ok_or_else(|| anyhow!("{field}.width must be a positive integer"))?;
    let height = obj
        .get("height")
        .and_then(|v| v.as_i64())
        .filter(|n| *n > 0)
        .ok_or_else(|| anyhow!("{field}.height must be a positive integer"))?;
    Ok(Some(Viewport { width, height }))
}

async fn wait_for_selector(page: &Page, selector: &str, timeout_ms: u64) -> Result<()> {
    let sel = selector.to_string();
    let deadline = tokio::time::Instant::now() + Duration::from_millis(timeout_ms);
    loop {
        if page.find_element(sel.clone()).await.is_ok() {
            return Ok(());
        }
        if tokio::time::Instant::now() >= deadline {
            bail!("timed out waiting for selector {sel}");
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

async fn wait_until<F, Fut>(mut check: F, timeout_ms: u64) -> Result<()>
where
    F: FnMut() -> Fut,
    Fut: std::future::Future<Output = Result<bool>>,
{
    let deadline = tokio::time::Instant::now() + Duration::from_millis(timeout_ms);
    loop {
        if check().await.unwrap_or(false) {
            return Ok(());
        }
        if tokio::time::Instant::now() >= deadline {
            bail!("timed out");
        }
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
}

// ---- tool defs ------------------------------------------------------------

fn tool_defs() -> Vec<Tool> {
    let str_t = obj(&[("type", Value::String("string".into()))]);
    let bool_t = obj(&[("type", Value::String("boolean".into()))]);
    let pos_int_t = obj(&[
        ("type", Value::String("integer".into())),
        ("minimum", json!(1)),
    ]);
    let nonneg_int_t = obj(&[
        ("type", Value::String("integer".into())),
        ("minimum", json!(0)),
    ]);
    let url_t = obj(&[
        ("type", Value::String("string".into())),
        ("format", Value::String("uri".into())),
    ]);
    let viewport_t = obj(&[
        ("type", Value::String("object".into())),
        (
            "properties",
            json!({
                "width": pos_int_t.clone(),
                "height": pos_int_t.clone(),
            }),
        ),
        ("required", json!(["width", "height"])),
        ("additionalProperties", Value::Bool(false)),
    ]);
    vec![
        tool(
            "open_browser_session",
            "Open a new isolated browser session and return its sessionId. Pass this id to every subsequent tool call. Sessions are full BrowserContexts — each has its own cookies, storage, and tabs.",
            object_schema(&[("viewport", &viewport_t), ("useMobileUA", &bool_t)], &[]),
        ),
        tool(
            "close_browser_session",
            "Close a browser session. Releases its tabs, cookies, and storage. Idempotent.",
            object_schema(&[("sessionId", &str_t)], &["sessionId"]),
        ),
        tool(
            "list_browser_sessions",
            "List active browser sessions on the underlying Chrome.",
            empty_obj_schema(),
        ),
        tool(
            "new_page",
            "Open a new tab in the session. Subsequent tool calls target this new tab.",
            object_schema(&[("sessionId", &str_t), ("url", &url_t)], &["sessionId"]),
        ),
        tool(
            "list_pages",
            "List all tabs open in the session.",
            object_schema(&[("sessionId", &str_t)], &["sessionId"]),
        ),
        tool(
            "navigate",
            "Navigate the session's active page to a URL. Resolves after the load event.",
            object_schema(
                &[
                    ("sessionId", &str_t),
                    ("url", &url_t),
                    ("timeout", &pos_int_t),
                ],
                &["sessionId", "url"],
            ),
        ),
        tool(
            "take_screenshot",
            "Capture a PNG screenshot of the session's active page. Returns the image as base64 embedded in the response.",
            object_schema(
                &[("sessionId", &str_t), ("fullPage", &bool_t)],
                &["sessionId"],
            ),
        ),
        tool(
            "take_snapshot",
            "Capture the accessibility tree of the session's active page as indented text.",
            object_schema(&[("sessionId", &str_t)], &["sessionId"]),
        ),
        tool(
            "click",
            "Click the first element matching the CSS selector.",
            object_schema(
                &[
                    ("sessionId", &str_t),
                    ("selector", &str_t),
                    ("timeout", &pos_int_t),
                ],
                &["sessionId", "selector"],
            ),
        ),
        tool(
            "type",
            "Type text into the first element matching the CSS selector.",
            object_schema(
                &[
                    ("sessionId", &str_t),
                    ("selector", &str_t),
                    ("text", &str_t),
                    ("delay", &nonneg_int_t),
                    ("clear", &bool_t),
                ],
                &["sessionId", "selector", "text"],
            ),
        ),
        tool(
            "wait_for",
            "Wait for a CSS selector to appear, or for a text string to be present in the page body.",
            object_schema(
                &[
                    ("sessionId", &str_t),
                    ("selector", &str_t),
                    ("text", &str_t),
                    ("timeout", &pos_int_t),
                ],
                &["sessionId"],
            ),
        ),
        tool(
            "evaluate",
            "Run a JavaScript expression in the page and return its value. Wrap with `return ...` for multi-statement bodies.",
            object_schema(
                &[("sessionId", &str_t), ("expression", &str_t)],
                &["sessionId", "expression"],
            ),
        ),
        tool(
            "list_visits",
            "List page visits in this session, oldest first. Each visit is one top-level navigation in one tab.",
            object_schema(&[("sessionId", &str_t)], &["sessionId"]),
        ),
        tool(
            "list_console_messages",
            "List console messages emitted by the session. Returns up to `limit` most-recent entries (default 500).",
            object_schema(
                &[
                    ("sessionId", &str_t),
                    ("visit", &pos_int_t),
                    ("limit", &pos_int_t),
                ],
                &["sessionId"],
            ),
        ),
        tool(
            "list_network_requests",
            "List network requests made by the session. Returns up to `limit` most-recent entries (default 500).",
            object_schema(
                &[
                    ("sessionId", &str_t),
                    ("visit", &pos_int_t),
                    ("limit", &pos_int_t),
                ],
                &["sessionId"],
            ),
        ),
        tool(
            "save_browser_state",
            "Save the session's cookies under a name so a future session can load them and resume without logging in again.",
            object_schema(
                &[("sessionId", &str_t), ("name", &str_t)],
                &["sessionId", "name"],
            ),
        ),
        tool(
            "load_browser_state",
            "Load a previously saved set of cookies into this session.",
            object_schema(
                &[("sessionId", &str_t), ("name", &str_t)],
                &["sessionId", "name"],
            ),
        ),
        tool(
            "list_browser_states",
            "List all saved browser states.",
            empty_obj_schema(),
        ),
        tool(
            "delete_browser_state",
            "Delete a saved browser state by name.",
            object_schema(&[("name", &str_t)], &["name"]),
        ),
    ]
}

fn tool(name: &'static str, description: &'static str, schema: JsonObject) -> Tool {
    Tool::new(name.to_string(), description.to_string(), Arc::new(schema))
}

fn obj(pairs: &[(&str, Value)]) -> Value {
    let mut m = Map::new();
    for (k, v) in pairs {
        m.insert((*k).into(), v.clone());
    }
    Value::Object(m)
}

fn empty_obj_schema() -> JsonObject {
    let mut m = Map::new();
    m.insert("type".into(), Value::String("object".into()));
    m.insert("properties".into(), Value::Object(Map::new()));
    m.insert("additionalProperties".into(), Value::Bool(false));
    m
}

fn object_schema(props: &[(&str, &Value)], required: &[&str]) -> JsonObject {
    let mut properties = Map::new();
    for (k, v) in props {
        properties.insert((*k).into(), (*v).clone());
    }
    let mut m = Map::new();
    m.insert("type".into(), Value::String("object".into()));
    m.insert("properties".into(), Value::Object(properties));
    if !required.is_empty() {
        m.insert(
            "required".into(),
            Value::Array(
                required
                    .iter()
                    .map(|s| Value::String((*s).into()))
                    .collect(),
            ),
        );
    }
    m.insert("additionalProperties".into(), Value::Bool(false));
    m
}
