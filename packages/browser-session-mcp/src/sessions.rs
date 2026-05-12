//! Maps the public sessionId (string) onto a chromiumoxide BrowserContextId.
//!
//! sessionId == BrowserContextId, so sessions survive this MCP subprocess
//! restarting — a fresh subprocess can connect to Chrome and find the same
//! contexts by id.
//!
//! Console + network capture lives in the listener daemon; this module only
//! handles the lifecycle + active page lookup.
use anyhow::{Context, Result, anyhow, bail};
use chromiumoxide::Browser;
use chromiumoxide::Page;
use chromiumoxide::cdp::browser_protocol::{
    browser::BrowserContextId,
    emulation::SetDeviceMetricsOverrideParams,
    network::SetUserAgentOverrideParams,
    target::{
        CreateBrowserContextParams, CreateTargetParams, GetTargetsParams, TargetId, TargetInfo,
    },
};
use serde::Serialize;

use crate::state::StateStore;
use crate::user_agent::{self, UaOverride};

#[derive(Debug, Clone, Serialize)]
pub struct SessionInfo {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    #[serde(rename = "pageCount")]
    pub page_count: usize,
    #[serde(rename = "activeUrl")]
    pub active_url: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub struct Viewport {
    pub width: i64,
    pub height: i64,
}

impl Default for Viewport {
    fn default() -> Self {
        Self {
            width: 1280,
            height: 800,
        }
    }
}

pub struct SessionManager {
    browser: Browser,
    state: StateStore,
}

impl SessionManager {
    pub fn new(browser: Browser, state: StateStore) -> Self {
        Self { browser, state }
    }

    pub fn browser(&self) -> &Browser {
        &self.browser
    }

    pub async fn open(
        &self,
        viewport: Option<Viewport>,
        use_mobile_ua: bool,
    ) -> Result<SessionInfo> {
        let override_ = user_agent::resolve(&self.browser, use_mobile_ua).await?;
        let ctx_id = self
            .browser
            .create_browser_context(CreateBrowserContextParams::default())
            .await
            .context("Target.createBrowserContext")?;
        let session_id = ctx_id.inner().to_string();

        self.state
            .set_user_agent_override(&session_id, &override_)
            .await;

        // Create the initial page in the new context. If anything below fails
        // we dispose the context AND drop the state record so we don't leak a
        // half-initialized session for the reaper to clean up later.
        let page = match self
            .browser
            .new_page(
                CreateTargetParams::builder()
                    .url("about:blank")
                    .browser_context_id(ctx_id.clone())
                    .build()
                    .map_err(|e| anyhow!("CreateTargetParams: {e}"))?,
            )
            .await
        {
            Ok(p) => p,
            Err(err) => {
                self.cleanup_failed_open(&session_id, ctx_id).await;
                return Err(anyhow!(err).context("Target.createTarget"));
            }
        };

        if let Err(err) = self.apply_user_agent(&page, &override_).await {
            self.cleanup_failed_open(&session_id, ctx_id).await;
            return Err(err);
        }

        let vp = viewport.unwrap_or_default();
        if let Err(err) = self.apply_viewport(&page, vp).await {
            self.cleanup_failed_open(&session_id, ctx_id).await;
            return Err(err);
        }

        self.state.touch(&session_id).await;
        Ok(SessionInfo {
            session_id,
            page_count: 1,
            active_url: Some("about:blank".to_string()),
        })
    }

    async fn cleanup_failed_open(&self, session_id: &str, ctx_id: BrowserContextId) {
        let _ = self.browser.dispose_browser_context(ctx_id).await;
        self.state.forget(session_id).await;
    }

    pub async fn close(&self, session_id: &str) -> Result<()> {
        let ctx_id = parse_context_id(session_id);
        self.browser
            .dispose_browser_context(ctx_id)
            .await
            .context("Target.disposeBrowserContext")?;
        self.state.forget(session_id).await;
        Ok(())
    }

    pub async fn list(&self) -> Result<Vec<SessionInfo>> {
        let targets = self.page_targets().await?;
        let mut by_ctx: std::collections::BTreeMap<String, Vec<TargetInfo>> =
            std::collections::BTreeMap::new();
        for t in targets {
            if let Some(ref ctx) = t.browser_context_id {
                by_ctx.entry(ctx.inner().to_string()).or_default().push(t);
            }
        }
        let mut out = Vec::new();
        for (session_id, pages) in by_ctx {
            let active_url = pages.last().map(|p| p.url.clone());
            out.push(SessionInfo {
                session_id,
                page_count: pages.len(),
                active_url,
            });
        }
        Ok(out)
    }

    pub async fn context_id_for(&self, session_id: &str) -> Result<BrowserContextId> {
        // Must hit Chrome to confirm the context still exists, since the MCP
        // process can be recycled out of sync with reality.
        let targets = self.page_targets().await?;
        let exists = targets.iter().any(|t| {
            t.browser_context_id
                .as_ref()
                .map(|c| c.inner() == session_id)
                .unwrap_or(false)
        });
        if !exists {
            // Edge case: a context with no pages still exists. Check
            // Target.getBrowserContexts to be sure before erroring out.
            let contexts = self.list_context_ids().await?;
            if !contexts.iter().any(|c| c.inner() == session_id) {
                bail!("Session not found: {session_id}. Call open_browser_session first.");
            }
        }
        self.state.touch(session_id).await;
        Ok(parse_context_id(session_id))
    }

    pub async fn active_page(&self, session_id: &str) -> Result<Page> {
        let _ctx = self.context_id_for(session_id).await?;
        let targets = self.page_targets().await?;
        let target = targets
            .into_iter()
            .filter(|t| {
                t.browser_context_id
                    .as_ref()
                    .map(|c| c.inner() == session_id)
                    .unwrap_or(false)
            })
            .next_back();
        let target = match target {
            Some(t) => t,
            None => {
                // No page yet — open one and apply UA.
                return self.new_page(session_id, None).await;
            }
        };
        let page = self
            .browser
            .get_page(TargetId::new(target.target_id.inner()))
            .await
            .context("Browser::get_page")?;
        Ok(page)
    }

    pub async fn new_page(&self, session_id: &str, url: Option<&str>) -> Result<Page> {
        let ctx_id = self.context_id_for(session_id).await?;
        let target_url = url.unwrap_or("about:blank").to_string();
        let page = self
            .browser
            .new_page(
                CreateTargetParams::builder()
                    .url(target_url)
                    .browser_context_id(ctx_id)
                    .build()
                    .map_err(|e| anyhow!("CreateTargetParams: {e}"))?,
            )
            .await
            .context("Target.createTarget")?;
        if let Some(override_) = self.state.user_agent_override(session_id).await {
            self.apply_user_agent(&page, &override_).await?;
        }
        Ok(page)
    }

    pub async fn pages(&self, session_id: &str) -> Result<Vec<Page>> {
        let _ctx = self.context_id_for(session_id).await?;
        let targets = self.page_targets().await?;
        let mut out = Vec::new();
        for t in targets {
            if t.browser_context_id
                .as_ref()
                .map(|c| c.inner() == session_id)
                .unwrap_or(false)
            {
                if let Ok(p) = self
                    .browser
                    .get_page(TargetId::new(t.target_id.inner()))
                    .await
                {
                    out.push(p);
                }
            }
        }
        Ok(out)
    }

    async fn page_targets(&self) -> Result<Vec<TargetInfo>> {
        let mut result = self
            .browser
            .execute(GetTargetsParams::default())
            .await
            .context("Target.getTargets")?;
        let target_infos = std::mem::take(&mut result.result.target_infos);
        Ok(target_infos
            .into_iter()
            .filter(|t| t.r#type == "page")
            .collect())
    }

    async fn list_context_ids(&self) -> Result<Vec<BrowserContextId>> {
        use chromiumoxide::cdp::browser_protocol::target::GetBrowserContextsParams;
        let mut result = self
            .browser
            .execute(GetBrowserContextsParams::default())
            .await
            .context("Target.getBrowserContexts")?;
        Ok(std::mem::take(&mut result.result.browser_context_ids))
    }

    async fn apply_user_agent(&self, page: &Page, override_: &UaOverride) -> Result<()> {
        let params: SetUserAgentOverrideParams = serde_json::from_value(serde_json::json!({
            "userAgent": override_.user_agent,
            "userAgentMetadata": override_.metadata,
        }))
        .context("constructing SetUserAgentOverrideParams from UA override")?;
        page.execute(params)
            .await
            .context("Network.setUserAgentOverride")?;
        Ok(())
    }

    async fn apply_viewport(&self, page: &Page, vp: Viewport) -> Result<()> {
        let params = SetDeviceMetricsOverrideParams::builder()
            .width(vp.width)
            .height(vp.height)
            .device_scale_factor(1.0)
            .mobile(false)
            .build()
            .map_err(|e| anyhow!("SetDeviceMetricsOverrideParams: {e}"))?;
        page.execute(params)
            .await
            .context("Emulation.setDeviceMetricsOverride")?;
        Ok(())
    }
}

fn parse_context_id(session_id: &str) -> BrowserContextId {
    BrowserContextId::new(session_id.to_string())
}
