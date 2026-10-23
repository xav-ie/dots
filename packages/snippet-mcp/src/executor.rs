//! Runs a rendered code snippet through executor's own `execute` tool, so a
//! snippet call returns the program's result instead of its source. Executor v2's
//! sandbox has no `eval`/`Function`, so a caller cannot run returned code itself.
//!
//! Configured by `EXECUTOR_URL` (e.g. `http://127.0.0.1:38972`) plus the bearer
//! token: `EXECUTOR_AUTH_TOKEN`, or the `EXECUTOR_AUTH_TOKEN=` line of the dotenv
//! file named by `EXECUTOR_ENV_FILE` (read on every call, so rotations apply).
//! Unconfigured, snippets keep returning their rendered body.
use serde_json::{Value, json};
use std::{sync::OnceLock, time::Duration};

static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();

fn client() -> &'static reqwest::Client {
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            // Long enough for snippets that poll (agent jobs, builds).
            .timeout(Duration::from_secs(300))
            .build()
            .expect("building reqwest client")
    })
}

pub struct Endpoint {
    base: String,
    url: String,
    token: String,
}

/// The configured executor, or `None` when snippets should stay render-only.
pub fn endpoint() -> anyhow::Result<Option<Endpoint>> {
    let Some(base) = std::env::var("EXECUTOR_URL").ok().filter(|v| !v.is_empty()) else {
        return Ok(None);
    };
    let token = match std::env::var("EXECUTOR_AUTH_TOKEN").ok().filter(|v| !v.is_empty()) {
        Some(t) => t,
        None => {
            let path = std::env::var("EXECUTOR_ENV_FILE")
                .map_err(|_| anyhow::anyhow!("EXECUTOR_URL is set but no EXECUTOR_AUTH_TOKEN or EXECUTOR_ENV_FILE"))?;
            let raw = std::fs::read_to_string(&path)
                .map_err(|e| anyhow::anyhow!("reading {path}: {e}"))?;
            raw.lines()
                .find_map(|l| l.strip_prefix("EXECUTOR_AUTH_TOKEN="))
                .map(|t| t.trim().trim_matches(['"', '\'']).to_string())
                .filter(|t| !t.is_empty())
                .ok_or_else(|| anyhow::anyhow!("no EXECUTOR_AUTH_TOKEN line in {path}"))?
        }
    };
    let base = base.trim_end_matches('/').to_string();
    Ok(Some(Endpoint {
        url: format!("{base}/mcp"),
        base,
        token,
    }))
}

/// A JSON-RPC response arrives as plain JSON or as one `data: ` SSE frame.
fn parse_rpc(text: &str) -> anyhow::Result<Value> {
    // SSE streams may open with an empty priming `data:` frame; take the first
    // frame that carries a JSON object.
    let body = text
        .lines()
        .filter_map(|l| l.strip_prefix("data:").map(str::trim))
        .find(|d| d.starts_with('{'))
        .unwrap_or(text);
    Ok(serde_json::from_str(body)?)
}

impl Endpoint {
    /// GET an executor HTTP API path (e.g. `/v1/apps`) and decode its JSON.
    pub async fn get_json<T: serde::de::DeserializeOwned>(&self, path: &str) -> anyhow::Result<T> {
        let res = client()
            .get(format!("{}{path}", self.base))
            .bearer_auth(&self.token)
            .timeout(Duration::from_secs(60))
            .send()
            .await?;
        let status = res.status();
        if !status.is_success() {
            anyhow::bail!("executor returned {status} for {path}");
        }
        Ok(res.json().await?)
    }

    async fn post(&self, session: Option<&str>, body: Value) -> anyhow::Result<(Option<String>, Value)> {
        let mut req = client()
            .post(&self.url)
            .bearer_auth(&self.token)
            .header("content-type", "application/json")
            .header("accept", "application/json, text/event-stream")
            .json(&body);
        if let Some(s) = session {
            req = req.header("mcp-session-id", s);
        }
        let res = req.send().await?;
        let status = res.status();
        let session = res
            .headers()
            .get("mcp-session-id")
            .and_then(|v| v.to_str().ok())
            .map(str::to_string);
        let text = res.text().await?;
        if !status.is_success() {
            anyhow::bail!("executor returned {status}: {}", text.chars().take(300).collect::<String>());
        }
        let value = if text.trim().is_empty() { Value::Null } else { parse_rpc(&text)? };
        Ok((session, value))
    }

    /// Runs `code` with executor's `execute` tool and returns its text result
    /// unchanged: a completed value, an error, or a pending approval the caller
    /// can `resume`.
    pub async fn execute(&self, code: &str) -> anyhow::Result<String> {
        let (session, init) = self
            .post(
                None,
                json!({
                    "jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {
                        "protocolVersion": "2025-06-18",
                        "capabilities": {},
                        "clientInfo": { "name": "snippet-mcp", "version": env!("CARGO_PKG_VERSION") },
                    },
                }),
            )
            .await?;
        if let Some(err) = init.get("error") {
            anyhow::bail!("executor initialize failed: {err}");
        }
        let session = session.ok_or_else(|| anyhow::anyhow!("executor sent no mcp-session-id"))?;
        self.post(
            Some(&session),
            json!({ "jsonrpc": "2.0", "method": "notifications/initialized" }),
        )
        .await?;
        let (_, res) = self
            .post(
                Some(&session),
                json!({
                    "jsonrpc": "2.0", "id": 2, "method": "tools/call",
                    "params": { "name": "execute", "arguments": { "code": code } },
                }),
            )
            .await?;
        if let Some(err) = res.get("error") {
            anyhow::bail!("executor execute failed: {err}");
        }
        let result = &res["result"];
        let text = result["content"]
            .as_array()
            .map(|parts| {
                parts
                    .iter()
                    .filter_map(|p| p["text"].as_str())
                    .collect::<Vec<_>>()
                    .join("\n")
            })
            .unwrap_or_default();
        if result["isError"].as_bool() == Some(true) {
            anyhow::bail!("{text}");
        }
        unwrap_execution(&result["structuredContent"]).map_or(Ok(text), |r| r)
    }
}

/// A completed run returns just its value, a failed one its error. Anything else
/// (a pending approval to `resume`, a paused input request) passes through whole.
fn unwrap_execution(sc: &Value) -> Option<anyhow::Result<String>> {
    if sc["status"].as_str() != Some("completed") {
        return None;
    }
    let exec = &sc["execution"];
    Some(match exec["ok"].as_bool() {
        Some(true) => Ok(match &exec["value"] {
            Value::String(s) => s.clone(),
            v => serde_json::to_string_pretty(v).unwrap_or_default(),
        }),
        Some(false) => Err(anyhow::anyhow!(
            "snippet failed: {}",
            exec["error"]["message"].as_str().map_or_else(|| exec["error"].to_string(), str::to_string)
        )),
        None => return None,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_plain_and_sse() {
        assert_eq!(parse_rpc(r#"{"id":1}"#).unwrap()["id"], 1);
        assert_eq!(
            parse_rpc("event: message\ndata: {\"id\":2}\n\n").unwrap()["id"],
            2
        );
        assert_eq!(
            parse_rpc("data: \nid: 0\nretry: 3000\n\ndata: {\"id\":3}\n").unwrap()["id"],
            3
        );
    }
}
