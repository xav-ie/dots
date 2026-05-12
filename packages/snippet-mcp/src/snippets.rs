use crate::types::{Frontmatter, SaveInput, Snippet, SnippetKind, UpdateInput};
use anyhow::{Context, Result, anyhow, bail};
use regex::Regex;
use std::{
    fs,
    io::{self, ErrorKind, Write},
    path::PathBuf,
    sync::{LazyLock, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};

static NAME_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[a-z][a-z0-9_]*$").unwrap());

// Names that collide with our management tools after executor's leading-`_`
// stripping. A snippet called e.g. "list.md" would shadow `_list` in
// executor's catalog (both end up at path `snippets.list`).
const RESERVED_NAMES: &[&str] = &["list", "get", "save", "update", "delete"];

pub struct Registry {
    dir: PathBuf,
    write_lock: Mutex<()>,
}

impl Registry {
    pub fn new(dir: PathBuf) -> Self {
        Self {
            dir,
            write_lock: Mutex::new(()),
        }
    }

    pub fn ensure_dir(&self) -> io::Result<()> {
        fs::create_dir_all(&self.dir)
    }

    pub fn list(&self) -> Result<Vec<Snippet>> {
        self.ensure_dir().context("creating snippets dir")?;
        let mut out = Vec::new();
        let entries = fs::read_dir(&self.dir).context("reading snippets dir")?;
        for entry in entries {
            let entry = match entry {
                Ok(e) => e,
                Err(err) => {
                    tracing::warn!(error = %err, "skipping unreadable dirent");
                    continue;
                }
            };
            let path = entry.path();
            let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            if path.extension().is_none_or(|e| e != "md") {
                continue;
            }
            if stem == "README" {
                continue;
            }
            if !NAME_RE.is_match(stem) {
                continue;
            }
            match self.load(stem) {
                Ok(s) => out.push(s),
                Err(err) => {
                    tracing::warn!(snippet = stem, error = %err, "skipping invalid snippet");
                }
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(out)
    }

    pub fn load(&self, name: &str) -> Result<Snippet> {
        let path = self.path_for(name)?;
        let raw =
            fs::read_to_string(&path).with_context(|| format!("reading {}", path.display()))?;
        let (fm, body) =
            parse(&raw).with_context(|| format!("parsing frontmatter for snippet '{name}'"))?;
        Ok(Snippet {
            name: name.to_string(),
            frontmatter: fm,
            body,
        })
    }

    pub fn save(&self, input: SaveInput) -> Result<Snippet> {
        let path = self.path_for(&input.name)?;
        let _guard = self
            .write_lock
            .lock()
            .map_err(|_| anyhow!("write lock poisoned"))?;

        if !input.overwrite.unwrap_or(false) {
            match fs::metadata(&path) {
                Ok(_) => bail!(
                    "snippet '{}' already exists (pass overwrite:true to replace)",
                    input.name
                ),
                Err(e) if e.kind() == ErrorKind::NotFound => {}
                Err(e) => return Err(e).context("checking existing snippet"),
            }
        }
        let fm = Frontmatter {
            description: required_non_empty(&input.description, "description")?,
            args: input.args,
            tags: input.tags,
            kind: Some(input.kind.unwrap_or(SnippetKind::Code)),
        };
        let body = input.body.trim_end_matches('\n').to_string();
        let serialized = serialize(&fm, &body)?;
        self.ensure_dir().context("creating snippets dir")?;
        atomic_write(&path, serialized.as_bytes())
            .with_context(|| format!("writing {}", path.display()))?;
        drop(_guard);
        self.load(&input.name)
    }

    pub fn update(&self, input: UpdateInput) -> Result<Snippet> {
        if let Some(desc) = &input.description {
            required_non_empty(desc, "description")?;
        }
        let _guard = self
            .write_lock
            .lock()
            .map_err(|_| anyhow!("write lock poisoned"))?;
        let current = self.load(&input.name)?;
        let next = SaveInput {
            name: input.name,
            description: input.description.unwrap_or(current.frontmatter.description),
            body: input.body.unwrap_or(current.body),
            args: input.args.or(current.frontmatter.args),
            tags: input.tags.or(current.frontmatter.tags),
            kind: input.kind.or(current.frontmatter.kind),
            overwrite: Some(true),
        };
        drop(_guard); // save() takes the lock itself
        self.save(next)
    }

    pub fn delete(&self, name: &str) -> Result<()> {
        let path = self.path_for(name)?;
        let _guard = self
            .write_lock
            .lock()
            .map_err(|_| anyhow!("write lock poisoned"))?;
        fs::remove_file(&path).with_context(|| format!("deleting snippet '{name}'"))
    }

    fn path_for(&self, name: &str) -> Result<PathBuf> {
        assert_name(name)?;
        let path = self.dir.join(format!("{name}.md"));
        // Defense-in-depth: even if NAME_RE relaxes, the resolved path must
        // sit directly inside self.dir.
        if path.parent() != Some(self.dir.as_path()) {
            bail!("internal error: snippet path escapes snippets dir");
        }
        Ok(path)
    }
}

fn assert_name(name: &str) -> Result<()> {
    if !NAME_RE.is_match(name) {
        bail!("invalid snippet name '{name}': must match ^[a-z][a-z0-9_]*$");
    }
    if RESERVED_NAMES.contains(&name) {
        bail!(
            "snippet name '{name}' is reserved (collides with the management tool of the same name)"
        );
    }
    Ok(())
}

fn required_non_empty(s: &str, field: &str) -> Result<String> {
    if s.trim().is_empty() {
        bail!("{field} must be a non-empty string");
    }
    Ok(s.to_string())
}

/// Detect frontmatter as the YAML block between a leading `---` line and the
/// next line that is exactly `---` (line-based, no substring fallback).
fn parse(raw: &str) -> Result<(Frontmatter, String)> {
    let mut lines = raw.split_inclusive('\n');
    let first = lines
        .next()
        .ok_or_else(|| anyhow!("empty file"))?
        .trim_end_matches(['\r', '\n']);
    if first != "---" {
        bail!("missing leading frontmatter delimiter '---'");
    }
    let mut yaml = String::new();
    let mut found_close = false;
    let mut body = String::new();
    let mut in_body = false;
    for line in lines {
        if in_body {
            body.push_str(line);
            continue;
        }
        let trimmed = line.trim_end_matches(['\r', '\n']);
        if trimmed == "---" {
            found_close = true;
            in_body = true;
            continue;
        }
        yaml.push_str(line);
    }
    if !found_close {
        bail!("missing closing frontmatter delimiter '---'");
    }
    let fm: Frontmatter = serde_yaml_ng::from_str(&yaml).context("yaml frontmatter")?;
    if fm.description.trim().is_empty() {
        bail!("description must be a non-empty string");
    }
    Ok((fm, body.trim_start_matches('\n').to_string()))
}

fn serialize(fm: &Frontmatter, body: &str) -> Result<String> {
    let yaml = serde_yaml_ng::to_string(fm).context("serializing frontmatter")?;
    Ok(format!("---\n{yaml}---\n\n{body}\n"))
}

fn atomic_write(path: &std::path::Path, bytes: &[u8]) -> io::Result<()> {
    let dir = path
        .parent()
        .ok_or_else(|| io::Error::new(ErrorKind::InvalidInput, "no parent dir"))?;
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let pid = std::process::id();
    let tmp = dir.join(format!(
        ".{}.tmp.{pid}.{nanos}",
        path.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("snippet")
    ));
    let mut f = fs::OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&tmp)?;
    let write_result = f.write_all(bytes).and_then(|()| f.sync_all());
    drop(f);
    if let Err(e) = write_result {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    fs::rename(&tmp, path)
}
