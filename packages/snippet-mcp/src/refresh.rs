//! Best-effort catalog refresh against the executor host.
//!
//! Executor's refresh endpoint is `POST /api/scopes/<scopeId>/mcp/sources/refresh`
//! with body `{ "namespace": "<source-id>" }`. The `scopeId` is workspace-
//! specific and not stable across workspace recreations, so the client
//! discovers it once by listing sources under the `default-scope` alias and
//! caches the result for the lifetime of the process.
use serde::Deserialize;
use serde_json::json;
use std::{sync::OnceLock, time::Duration};
use tokio::sync::OnceCell;

pub struct RefreshOutcome {
    pub ok: bool,
    pub detail: String,
}

static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();
static SCOPE_CACHE: OnceCell<Result<String, String>> = OnceCell::const_new();

fn client() -> &'static reqwest::Client {
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .expect("building reqwest client")
    })
}

#[derive(Deserialize)]
struct SourceEntry {
    id: String,
    #[serde(rename = "scopeId")]
    scope_id: Option<String>,
}

pub async fn refresh_executor() -> RefreshOutcome {
    let base = match std::env::var("EXECUTOR_BASE_URL") {
        Ok(v) if !v.is_empty() => v.trim_end_matches('/').to_string(),
        _ => {
            return RefreshOutcome {
                ok: false,
                detail: "EXECUTOR_BASE_URL not set".into(),
            };
        }
    };
    let namespace =
        std::env::var("EXECUTOR_REFRESH_NAMESPACE").unwrap_or_else(|_| "snippets".to_string());

    let scope_result = SCOPE_CACHE
        .get_or_init(|| async {
            discover_scope(&base, &namespace)
                .await
                .map_err(|e| e.to_string())
        })
        .await;
    let scope_id = match scope_result {
        Ok(id) => id,
        Err(detail) => {
            return RefreshOutcome {
                ok: false,
                detail: format!("scope discovery: {detail}"),
            };
        }
    };

    let url = format!("{base}/api/scopes/{scope_id}/mcp/sources/refresh");
    match client()
        .post(&url)
        .json(&json!({ "namespace": namespace }))
        .send()
        .await
    {
        Ok(res) if res.status().is_success() => RefreshOutcome {
            ok: true,
            detail: "ok".into(),
        },
        Ok(res) => RefreshOutcome {
            ok: false,
            detail: format!("executor returned {}", res.status()),
        },
        Err(err) => RefreshOutcome {
            ok: false,
            detail: err.to_string(),
        },
    }
}

async fn discover_scope(base: &str, namespace: &str) -> Result<String, anyhow::Error> {
    // `default-scope` is executor's well-known alias for "list every source in
    // the workspace, regardless of which scope hosts it". The actual scope id
    // (e.g. `executor-web-e72c47e3`) lives on each source entry.
    let url = format!("{base}/api/scopes/default-scope/sources");
    let entries: Vec<SourceEntry> = client()
        .get(&url)
        .send()
        .await?
        .error_for_status()?
        .json()
        .await?;
    entries
        .into_iter()
        .find(|e| e.id == namespace)
        .and_then(|e| e.scope_id)
        .ok_or_else(|| anyhow::anyhow!("no source matching namespace '{namespace}'"))
}
