//! Per-visit NDJSON event log.
//!
//! Layout: `<logs_dir>/<sessionId>/<seq:05>-<targetId>.ndjson`.
//!
//! Each file starts with a `{"kind":"visit",...}` header line. Subsequent
//! lines are console + network events. The listener opens a new file on every
//! top-level navigation; the MCP server reads them lazily.
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::Arc,
};
use time::{OffsetDateTime, format_description::well_known::Rfc3339};
use tokio::{
    fs,
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    sync::Mutex,
};

const SEQ_PAD: usize = 5;

pub fn default_logs_dir() -> PathBuf {
    std::env::var_os("LOGS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/var/lib/browser-session-mcp/logs"))
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind")]
pub enum LogLine {
    #[serde(rename = "visit")]
    Visit(VisitHeader),
    #[serde(rename = "console")]
    Console(ConsoleEntry),
    #[serde(rename = "network")]
    Network(NetworkEntry),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VisitHeader {
    pub seq: u32,
    #[serde(rename = "targetId")]
    pub target_id: String,
    pub url: String,
    #[serde(rename = "openedAt")]
    pub opened_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsoleEntry {
    pub t: String,
    #[serde(rename = "type")]
    pub ty: String,
    pub text: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NetworkEntry {
    pub t: String,
    pub method: String,
    pub url: String,
    pub status: Option<i64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub failure: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogKind {
    Console,
    Network,
}

#[derive(Clone)]
pub struct LogWriter {
    logs_dir: PathBuf,
    next_seqs: Arc<Mutex<HashMap<String, u32>>>,
}

impl LogWriter {
    pub fn new(logs_dir: PathBuf) -> Self {
        Self {
            logs_dir,
            next_seqs: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub async fn open_visit(&self, session_id: &str, target_id: &str, url: &str) -> Result<u32> {
        let dir = session_dir(&self.logs_dir, session_id);
        fs::create_dir_all(&dir)
            .await
            .with_context(|| format!("mkdir -p {}", dir.display()))?;
        let seq = self.next_seq(session_id, &dir).await?;
        let header = VisitHeader {
            seq,
            target_id: target_id.to_string(),
            url: url.to_string(),
            opened_at: now_rfc3339(),
        };
        let line = serde_json::to_string(&LogLine::Visit(header))?;
        let path = visit_file(&self.logs_dir, session_id, seq, target_id);
        append_line(&path, &line).await?;
        Ok(seq)
    }

    pub async fn append_console(
        &self,
        session_id: &str,
        seq: u32,
        target_id: &str,
        entry: ConsoleEntry,
    ) -> Result<()> {
        let path = visit_file(&self.logs_dir, session_id, seq, target_id);
        let line = serde_json::to_string(&LogLine::Console(entry))?;
        append_line(&path, &line).await
    }

    pub async fn append_network(
        &self,
        session_id: &str,
        seq: u32,
        target_id: &str,
        entry: NetworkEntry,
    ) -> Result<()> {
        let path = visit_file(&self.logs_dir, session_id, seq, target_id);
        let line = serde_json::to_string(&LogLine::Network(entry))?;
        append_line(&path, &line).await
    }

    pub async fn close_session(&self, session_id: &str) -> Result<()> {
        self.next_seqs.lock().await.remove(session_id);
        let dir = session_dir(&self.logs_dir, session_id);
        match fs::remove_dir_all(&dir).await {
            Ok(()) => Ok(()),
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(err) => Err(err).context(format!("rm -rf {}", dir.display())),
        }
    }

    async fn next_seq(&self, session_id: &str, dir: &Path) -> Result<u32> {
        let mut guard = self.next_seqs.lock().await;
        if let Some(n) = guard.get(session_id).copied() {
            guard.insert(session_id.to_string(), n + 1);
            return Ok(n);
        }
        let mut max = 0u32;
        if let Ok(mut entries) = fs::read_dir(dir).await {
            while let Some(entry) = entries.next_entry().await? {
                if let Some(name) = entry.file_name().to_str() {
                    if let Some(seq) = seq_from_filename(name) {
                        if seq > max {
                            max = seq;
                        }
                    }
                }
            }
        }
        let seq = max + 1;
        guard.insert(session_id.to_string(), seq + 1);
        Ok(seq)
    }
}

pub async fn read_visits(logs_dir: &Path, session_id: &str) -> Result<Vec<VisitHeader>> {
    let dir = session_dir(logs_dir, session_id);
    let files = ordered_files(&dir, None).await?;
    let mut out = Vec::new();
    for f in files {
        let path = dir.join(&f);
        let file = match fs::File::open(&path).await {
            Ok(f) => f,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => continue,
            Err(err) => return Err(err).context(format!("opening {}", path.display())),
        };
        let mut reader = BufReader::new(file);
        let mut first = String::new();
        if reader.read_line(&mut first).await? == 0 {
            continue;
        }
        let line = first.trim_end_matches(['\r', '\n']);
        if let Ok(LogLine::Visit(v)) = serde_json::from_str::<LogLine>(line) {
            out.push(v);
        }
    }
    Ok(out)
}

pub struct ReadOpts {
    pub kind: Option<LogKind>,
    pub limit: Option<usize>,
    pub visit: Option<u32>,
}

pub enum SessionLogEntry {
    Console(ConsoleEntry),
    Network(NetworkEntry),
}

pub async fn read_session_logs(
    logs_dir: &Path,
    session_id: &str,
    opts: ReadOpts,
) -> Result<Vec<SessionLogEntry>> {
    let dir = session_dir(logs_dir, session_id);
    let files = ordered_files(&dir, opts.visit).await?;
    let mut out: Vec<SessionLogEntry> = Vec::new();
    for f in files {
        let path = dir.join(&f);
        let file = match fs::File::open(&path).await {
            Ok(f) => f,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => continue,
            Err(err) => return Err(err).context(format!("opening {}", path.display())),
        };
        let mut reader = BufReader::new(file).lines();
        while let Some(line) = reader.next_line().await? {
            if line.is_empty() {
                continue;
            }
            let parsed: LogLine = match serde_json::from_str(&line) {
                Ok(v) => v,
                Err(_) => continue,
            };
            match parsed {
                LogLine::Visit(_) => continue,
                LogLine::Console(c) => {
                    if matches!(opts.kind, Some(LogKind::Network)) {
                        continue;
                    }
                    out.push(SessionLogEntry::Console(c));
                }
                LogLine::Network(n) => {
                    if matches!(opts.kind, Some(LogKind::Console)) {
                        continue;
                    }
                    out.push(SessionLogEntry::Network(n));
                }
            }
        }
    }
    if let Some(limit) = opts.limit {
        if out.len() > limit {
            let start = out.len() - limit;
            out.drain(..start);
        }
    }
    Ok(out)
}

fn sanitize(s: &str) -> String {
    s.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '_' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

fn session_dir(logs_dir: &Path, session_id: &str) -> PathBuf {
    logs_dir.join(sanitize(session_id))
}

fn visit_file(logs_dir: &Path, session_id: &str, seq: u32, target_id: &str) -> PathBuf {
    session_dir(logs_dir, session_id).join(format!(
        "{:0width$}-{}.ndjson",
        seq,
        sanitize(target_id),
        width = SEQ_PAD
    ))
}

fn seq_from_filename(name: &str) -> Option<u32> {
    let head = name.split('-').next()?;
    head.parse().ok()
}

async fn ordered_files(dir: &Path, visit: Option<u32>) -> Result<Vec<String>> {
    let mut entries = match fs::read_dir(dir).await {
        Ok(e) => e,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(err) => return Err(err).context(format!("read_dir {}", dir.display())),
    };
    let mut out = Vec::new();
    while let Some(entry) = entries.next_entry().await? {
        if let Some(name) = entry.file_name().to_str() {
            if !name.ends_with(".ndjson") {
                continue;
            }
            if let Some(want) = visit {
                if seq_from_filename(name) != Some(want) {
                    continue;
                }
            }
            out.push(name.to_string());
        }
    }
    out.sort();
    Ok(out)
}

async fn append_line(path: &Path, line: &str) -> Result<()> {
    // Single write so O_APPEND keeps the {line + \n} atomic per call —
    // concurrent appenders never tear newlines across records.
    let mut buf = Vec::with_capacity(line.len() + 1);
    buf.extend_from_slice(line.as_bytes());
    buf.push(b'\n');
    let mut f = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .await
        .with_context(|| format!("opening {} for append", path.display()))?;
    f.write_all(&buf)
        .await
        .with_context(|| format!("writing {}", path.display()))?;
    Ok(())
}

fn now_rfc3339() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| String::new())
}
