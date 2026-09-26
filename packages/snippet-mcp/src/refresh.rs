//! Best-effort catalog refresh against the executor host.
//!
//! Executor's refresh endpoint is
//! `POST /api/connections/<owner>/<integration>/<name>/refresh`, authenticated
//! with the daemon's bearer token. The token is read from the file named by
//! `EXECUTOR_AUTH_TOKEN_FILE`: executor's own `server-control/auth.json`
//! (`{ "token": "..." }`), read on every refresh.
use serde::Deserialize;
use std::{sync::OnceLock, time::Duration};

pub struct RefreshOutcome {
    pub ok: bool,
    pub detail: String,
}

static CLIENT: OnceLock<reqwest::Client> = OnceLock::new();

fn client() -> &'static reqwest::Client {
    CLIENT.get_or_init(|| {
        reqwest::Client::builder()
            .timeout(Duration::from_secs(5))
            .build()
            .expect("building reqwest client")
    })
}

#[derive(Deserialize)]
struct AuthFile {
    token: String,
}

fn read_token() -> Result<String, String> {
    let path = std::env::var("EXECUTOR_AUTH_TOKEN_FILE")
        .map_err(|_| "EXECUTOR_AUTH_TOKEN_FILE not set".to_string())?;
    let raw = std::fs::read_to_string(&path).map_err(|e| format!("reading {path}: {e}"))?;
    serde_json::from_str::<AuthFile>(&raw)
        .map(|a| a.token)
        .map_err(|e| format!("parsing {path}: {e}"))
}

pub async fn refresh_executor() -> RefreshOutcome {
    let fail = |detail: String| RefreshOutcome { ok: false, detail };

    let base = match std::env::var("EXECUTOR_BASE_URL") {
        Ok(v) if !v.is_empty() => v.trim_end_matches('/').to_string(),
        _ => return fail("EXECUTOR_BASE_URL not set".into()),
    };
    let token = match read_token() {
        Ok(t) => t,
        Err(e) => return fail(e),
    };
    let integration =
        std::env::var("EXECUTOR_REFRESH_NAMESPACE").unwrap_or_else(|_| "snippets".to_string());
    let connection = std::env::var("EXECUTOR_REFRESH_CONNECTION")
        .unwrap_or_else(|_| "org/workspace".to_string());
    let Some((owner, name)) = connection.split_once('/') else {
        return fail(format!(
            "EXECUTOR_REFRESH_CONNECTION must be <owner>/<name>, got '{connection}'"
        ));
    };

    let url = format!("{base}/api/connections/{owner}/{integration}/{name}/refresh");
    match client().post(&url).bearer_auth(token).send().await {
        Ok(res) if res.status().is_success() => RefreshOutcome {
            ok: true,
            detail: "ok".into(),
        },
        Ok(res) => fail(format!("executor returned {}", res.status())),
        Err(err) => fail(err.to_string()),
    }
}
