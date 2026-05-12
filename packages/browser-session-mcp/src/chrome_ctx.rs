//! Lazy + reconnect-on-failure wrapper around the Chrome connection. The MCP
//! boots cleanly even if Chrome is down — we defer the connect to the first
//! tool call so transient outages don't cascade through mcp-proxy.
use anyhow::Result;
use std::sync::Arc;
use tokio::{sync::Mutex, task::JoinHandle};

use crate::chrome;
use crate::sessions::SessionManager;
use crate::state::StateStore;

#[derive(Clone)]
pub struct ChromeContext {
    browser_url: String,
    state: StateStore,
    inner: Arc<Mutex<Option<Connected>>>,
}

struct Connected {
    sessions: Arc<SessionManager>,
    _handler: JoinHandle<()>,
}

impl ChromeContext {
    pub fn new(browser_url: String, state: StateStore) -> Self {
        Self {
            browser_url,
            state,
            inner: Arc::new(Mutex::new(None)),
        }
    }

    pub fn state(&self) -> &StateStore {
        &self.state
    }

    pub async fn sessions(&self) -> Result<Arc<SessionManager>> {
        let mut guard = self.inner.lock().await;
        if let Some(c) = guard.as_ref() {
            return Ok(c.sessions.clone());
        }
        let (browser, handler) = chrome::connect(&self.browser_url).await?;
        let sm = Arc::new(SessionManager::new(browser, self.state.clone()));
        *guard = Some(Connected {
            sessions: sm.clone(),
            _handler: handler,
        });
        Ok(sm)
    }

    /// Force the next `sessions()` call to reconnect. Call this from tool
    /// handlers after an error that looks like a dropped connection.
    pub async fn invalidate(&self) {
        *self.inner.lock().await = None;
    }
}
