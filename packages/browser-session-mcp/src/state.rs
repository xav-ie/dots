//! Per-session metadata persisted to disk so the reaper can find idle
//! BrowserContexts after the MCP subprocess has been recycled.
//!
//! Writes are debounced (1s) and atomic (write to .tmp + rename) so a flurry
//! of tool calls doesn't thrash the filesystem and a crash mid-write doesn't
//! leave the file truncated.
use anyhow::{Context, Result, anyhow};
use serde::{Deserialize, Serialize};
use std::{collections::HashMap, path::PathBuf, sync::Arc, time::Duration};
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use tokio::{
    fs,
    sync::{Mutex, Notify},
};

use crate::user_agent::UaOverride;

pub fn default_state_file() -> PathBuf {
    std::env::var_os("STATE_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/var/lib/browser-session-mcp/state.json"))
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct SessionRecord {
    #[serde(rename = "lastUsedAt")]
    pub last_used_at: String,
    #[serde(rename = "userAgent", default, skip_serializing_if = "Option::is_none")]
    pub user_agent: Option<String>,
    #[serde(
        rename = "userAgentMetadata",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub user_agent_metadata: Option<serde_json::Value>,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct StateData {
    #[serde(default)]
    sessions: HashMap<String, SessionRecord>,
}

#[derive(Debug)]
struct Inner {
    data: StateData,
    dirty: bool,
}

#[derive(Clone)]
pub struct StateStore {
    file: PathBuf,
    inner: Arc<Mutex<Inner>>,
    notify: Arc<Notify>,
    /// Serializes the rename portion of atomic_write so flush_now and the
    /// background flusher can't race two stale-vs-fresh writes against the
    /// same file.
    write_lock: Arc<Mutex<()>>,
}

impl StateStore {
    pub async fn load(file: PathBuf) -> Result<Self> {
        let data = match fs::read_to_string(&file).await {
            Ok(raw) => serde_json::from_str::<StateData>(&raw).unwrap_or_default(),
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => StateData::default(),
            Err(err) => {
                tracing::warn!(file = %file.display(), error = %err, "failed to load state file; starting empty");
                StateData::default()
            }
        };
        let store = Self {
            file,
            inner: Arc::new(Mutex::new(Inner { data, dirty: false })),
            notify: Arc::new(Notify::new()),
            write_lock: Arc::new(Mutex::new(())),
        };
        store.spawn_flusher();
        Ok(store)
    }

    fn spawn_flusher(&self) {
        let file = self.file.clone();
        let inner = self.inner.clone();
        let notify = self.notify.clone();
        let write_lock = self.write_lock.clone();
        tokio::spawn(async move {
            loop {
                notify.notified().await;
                tokio::time::sleep(Duration::from_secs(1)).await;
                let _w = write_lock.lock().await;
                let payload = {
                    let mut guard = inner.lock().await;
                    if !guard.dirty {
                        continue;
                    }
                    guard.dirty = false;
                    serde_json::to_vec_pretty(&guard.data).ok()
                };
                let Some(bytes) = payload else {
                    continue;
                };
                if let Err(err) = atomic_write(&file, &bytes).await {
                    tracing::warn!(file = %file.display(), error = %err, "state flush failed; will retry");
                    let mut guard = inner.lock().await;
                    guard.dirty = true;
                    notify.notify_one();
                }
            }
        });
    }

    pub async fn touch(&self, session_id: &str) {
        let now = now_rfc3339();
        let mut guard = self.inner.lock().await;
        let rec = guard
            .data
            .sessions
            .entry(session_id.to_string())
            .or_default();
        rec.last_used_at = now;
        guard.dirty = true;
        self.notify.notify_one();
    }

    pub async fn set_user_agent_override(&self, session_id: &str, override_: &UaOverride) {
        let now = now_rfc3339();
        let mut guard = self.inner.lock().await;
        let rec = guard
            .data
            .sessions
            .entry(session_id.to_string())
            .or_default();
        if rec.last_used_at.is_empty() {
            rec.last_used_at = now;
        }
        rec.user_agent = Some(override_.user_agent.clone());
        rec.user_agent_metadata = Some(override_.metadata.clone());
        guard.dirty = true;
        self.notify.notify_one();
    }

    pub async fn user_agent_override(&self, session_id: &str) -> Option<UaOverride> {
        let guard = self.inner.lock().await;
        let rec = guard.data.sessions.get(session_id)?;
        Some(UaOverride {
            user_agent: rec.user_agent.clone()?,
            metadata: rec.user_agent_metadata.clone()?,
        })
    }

    pub async fn forget(&self, session_id: &str) {
        let mut guard = self.inner.lock().await;
        if guard.data.sessions.remove(session_id).is_some() {
            guard.dirty = true;
            self.notify.notify_one();
        }
    }

    pub async fn flush_now(&self) -> Result<()> {
        let _w = self.write_lock.lock().await;
        let bytes = {
            let mut guard = self.inner.lock().await;
            if !guard.dirty {
                return Ok(());
            }
            guard.dirty = false;
            serde_json::to_vec_pretty(&guard.data).context("serializing state")?
        };
        atomic_write(&self.file, &bytes).await
    }
}

fn now_rfc3339() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| String::new())
}

async fn atomic_write(file: &std::path::Path, bytes: &[u8]) -> Result<()> {
    if let Some(dir) = file.parent() {
        fs::create_dir_all(dir)
            .await
            .with_context(|| format!("mkdir -p {}", dir.display()))?;
    }
    let tmp = file.with_extension(
        file.extension()
            .and_then(|s| s.to_str())
            .map(|s| format!("{s}.tmp"))
            .unwrap_or_else(|| "tmp".to_string()),
    );
    fs::write(&tmp, bytes)
        .await
        .with_context(|| format!("writing {}", tmp.display()))?;
    fs::rename(&tmp, file)
        .await
        .with_context(|| format!("rename {} -> {}", tmp.display(), file.display()))?;
    Ok(())
}

/// Reaper helper: read the raw state file synchronously, without spawning
/// the background flusher. Returns parsed sessions.
pub async fn read_state_file(file: &std::path::Path) -> Result<HashMap<String, SessionRecord>> {
    match fs::read_to_string(file).await {
        Ok(raw) => {
            let data: StateData = serde_json::from_str(&raw)
                .with_context(|| format!("parsing {}", file.display()))?;
            Ok(data.sessions)
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(HashMap::new()),
        Err(err) => Err(anyhow!(err).context(format!("reading {}", file.display()))),
    }
}

/// Reaper helper: atomically rewrite the state file with the given sessions.
pub async fn write_state_file(
    file: &std::path::Path,
    sessions: &HashMap<String, SessionRecord>,
) -> Result<()> {
    let data = StateData {
        sessions: sessions.clone(),
    };
    let bytes = serde_json::to_vec_pretty(&data).context("serializing state")?;
    atomic_write(file, &bytes).await
}
