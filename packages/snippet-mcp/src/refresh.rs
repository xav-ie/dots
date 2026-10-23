//! Best-effort refresh of executor's tool search after a snippet is saved,
//! updated or deleted. Executor v2 re-reads an app's tools when its tool list is
//! requested, so this asks for the snippets app's tools once. Uses the same
//! EXECUTOR_URL and token as code-snippet execution (see `executor`); the app's
//! slug is `EXECUTOR_REFRESH_APP`, default `snippets`.
use crate::executor;
use serde::Deserialize;

pub struct RefreshOutcome {
    pub ok: bool,
    pub detail: String,
}

#[derive(Deserialize)]
struct App {
    id: String,
    slug: String,
}

pub async fn refresh_executor() -> RefreshOutcome {
    match refresh().await {
        Ok(()) => RefreshOutcome {
            ok: true,
            detail: "ok".into(),
        },
        Err(err) => RefreshOutcome {
            ok: false,
            detail: err.to_string(),
        },
    }
}

async fn refresh() -> anyhow::Result<()> {
    let endpoint = executor::endpoint()?.ok_or_else(|| anyhow::anyhow!("EXECUTOR_URL not set"))?;
    let slug = std::env::var("EXECUTOR_REFRESH_APP").unwrap_or_else(|_| "snippets".to_string());
    let apps: Vec<App> = endpoint.get_json("/v1/apps").await?;
    let app = apps
        .into_iter()
        .find(|a| a.slug == slug)
        .ok_or_else(|| anyhow::anyhow!("no executor app with slug '{slug}'"))?;
    endpoint
        .get_json::<serde_json::Value>(&format!("/v1/tools?app={}&limit=1", app.id))
        .await?;
    Ok(())
}
