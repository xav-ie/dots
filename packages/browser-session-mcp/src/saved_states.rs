//! Named cookie snapshots. Schema is forward-compatible — origins[] is empty
//! in v1 but reserved for localStorage / sessionStorage later. Files are
//! mode 0600 inside a mode 0700 directory so other users on the host can't
//! read auth tokens.
use anyhow::{Context, Result, anyhow, bail};
use once_cell::sync::Lazy;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::{os::unix::fs::DirBuilderExt, path::PathBuf};
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use tokio::{fs, io::AsyncWriteExt};

static NAME_RE: Lazy<Regex> = Lazy::new(|| Regex::new(r"^[A-Za-z0-9][A-Za-z0-9._-]*$").unwrap());

pub fn default_states_dir() -> PathBuf {
    std::env::var_os("STATES_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/var/lib/browser-session-mcp/states"))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SavedState {
    pub name: String,
    #[serde(rename = "savedAt")]
    pub saved_at: String,
    pub cookies: Vec<serde_json::Value>,
    #[serde(default)]
    pub origins: Vec<serde_json::Value>,
}

#[derive(Debug, Clone, Serialize)]
pub struct StateSummary {
    pub name: String,
    #[serde(rename = "savedAt")]
    pub saved_at: String,
    #[serde(rename = "cookieCount")]
    pub cookie_count: usize,
}

#[derive(Clone)]
pub struct SavedStateStore {
    dir: PathBuf,
}

impl SavedStateStore {
    pub fn new(dir: PathBuf) -> Self {
        Self { dir }
    }

    pub async fn save(&self, name: &str, cookies: Vec<serde_json::Value>) -> Result<SavedState> {
        validate_name(name)?;
        self.ensure_dir().await?;
        let state = SavedState {
            name: name.to_string(),
            saved_at: now_rfc3339(),
            cookies,
            origins: Vec::new(),
        };
        let file = self.file_for(name);
        let tmp = self.dir.join(format!(".{name}.json.tmp"));
        let bytes = serde_json::to_vec_pretty(&state).context("serializing saved state")?;
        let mut f = fs::OpenOptions::new()
            .create(true)
            .truncate(true)
            .write(true)
            .mode(0o600)
            .open(&tmp)
            .await
            .with_context(|| format!("creating {}", tmp.display()))?;
        f.write_all(&bytes)
            .await
            .with_context(|| format!("writing {}", tmp.display()))?;
        f.sync_all()
            .await
            .with_context(|| format!("fsync {}", tmp.display()))?;
        drop(f);
        fs::rename(&tmp, &file)
            .await
            .with_context(|| format!("rename {} -> {}", tmp.display(), file.display()))?;
        Ok(state)
    }

    pub async fn load(&self, name: &str) -> Result<SavedState> {
        validate_name(name)?;
        let file = self.file_for(name);
        let raw = match fs::read_to_string(&file).await {
            Ok(s) => s,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                bail!("No saved browser state named {name:?}.");
            }
            Err(err) => return Err(anyhow!(err).context(format!("reading {}", file.display()))),
        };
        serde_json::from_str(&raw).with_context(|| format!("parsing {}", file.display()))
    }

    pub async fn list(&self) -> Result<Vec<StateSummary>> {
        let mut out = Vec::new();
        let mut entries = match fs::read_dir(&self.dir).await {
            Ok(e) => e,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(out),
            Err(err) => {
                return Err(anyhow!(err)).context(format!("read_dir {}", self.dir.display()));
            }
        };
        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            if path.extension().is_none_or(|e| e != "json") {
                continue;
            }
            if !NAME_RE.is_match(stem) {
                continue;
            }
            match fs::read_to_string(&path).await {
                Ok(raw) => match serde_json::from_str::<SavedState>(&raw) {
                    Ok(parsed) => out.push(StateSummary {
                        name: parsed.name,
                        saved_at: parsed.saved_at,
                        cookie_count: parsed.cookies.len(),
                    }),
                    Err(err) => {
                        tracing::warn!(file = %path.display(), error = %err, "skipping corrupt saved state");
                    }
                },
                Err(err) => {
                    tracing::warn!(file = %path.display(), error = %err, "skipping unreadable saved state");
                }
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(out)
    }

    pub async fn delete(&self, name: &str) -> Result<bool> {
        validate_name(name)?;
        let file = self.file_for(name);
        match fs::remove_file(&file).await {
            Ok(()) => Ok(true),
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(false),
            Err(err) => Err(anyhow!(err)).context(format!("deleting {}", file.display())),
        }
    }

    async fn ensure_dir(&self) -> Result<()> {
        match fs::metadata(&self.dir).await {
            Ok(_) => Ok(()),
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                let dir = self.dir.clone();
                tokio::task::spawn_blocking(move || {
                    std::fs::DirBuilder::new()
                        .recursive(true)
                        .mode(0o700)
                        .create(&dir)
                })
                .await
                .context("spawn_blocking mkdir")?
                .with_context(|| format!("mkdir -p {}", self.dir.display()))?;
                Ok(())
            }
            Err(err) => Err(anyhow!(err)).context(format!("stat {}", self.dir.display())),
        }
    }

    fn file_for(&self, name: &str) -> PathBuf {
        self.dir.join(format!("{name}.json"))
    }
}

fn validate_name(name: &str) -> Result<()> {
    if !NAME_RE.is_match(name) {
        bail!("Invalid state name {name:?}. Use letters, digits, '.', '_', '-'.");
    }
    Ok(())
}

fn now_rfc3339() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| String::new())
}
