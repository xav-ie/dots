use crate::types::{Frontmatter, SaveInput, Snippet, SnippetKind, UpdateInput};
use anyhow::{Context, Result, anyhow, bail};
use regex::Regex;
use std::{
    collections::BTreeMap,
    fs,
    io::{self, ErrorKind, Write},
    path::{Path, PathBuf},
    sync::{LazyLock, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};

static NAME_RE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[a-z][a-z0-9_]*$").unwrap());

// Names that collide with our management tools after executor's leading-`_`
// stripping. A snippet called e.g. "list.md" would shadow `_list` in
// executor's catalog (both end up at path `snippets.list`).
const RESERVED_NAMES: &[&str] = &["list", "get", "save", "update", "delete"];

/// With an identity, every snippet lives in one age-encrypted JSON object
/// (`snippets.age`, name → markdown) so names stay hidden too.
const BUNDLE: &str = "snippets.age";

pub struct Registry {
    dir: PathBuf,
    /// When set, snippets are stored in the encrypted bundle, encrypted to
    /// this identity's own public key. Otherwise plaintext `<name>.md` files.
    identity: Option<age::x25519::Identity>,
    write_lock: Mutex<()>,
}

/// Reads the first x25519 secret key from an age key file.
// ponytail: single x25519 identity; switch to age::IdentityFile for multi-key or plugin keys.
pub fn load_identity(path: &Path) -> Result<age::x25519::Identity> {
    let raw = fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
    raw.lines()
        .map(str::trim)
        .find(|l| l.starts_with("AGE-SECRET-KEY-"))
        .ok_or_else(|| anyhow!("no AGE-SECRET-KEY in {}", path.display()))?
        .parse()
        .map_err(|e: &str| anyhow!("invalid age key in {}: {e}", path.display()))
}

impl Registry {
    pub fn new(dir: PathBuf, identity: Option<age::x25519::Identity>) -> Self {
        Self {
            dir,
            identity,
            write_lock: Mutex::new(()),
        }
    }

    pub fn ensure_dir(&self) -> io::Result<()> {
        fs::create_dir_all(&self.dir)
    }

    pub fn list(&self) -> Result<Vec<Snippet>> {
        let mut out = Vec::new();
        for name in self.names()? {
            match self.load(&name) {
                Ok(s) => out.push(s),
                Err(err) => {
                    tracing::warn!(snippet = name, error = %err, "skipping invalid snippet");
                }
            }
        }
        out.sort_by(|a, b| a.name.cmp(&b.name));
        Ok(out)
    }

    pub fn load(&self, name: &str) -> Result<Snippet> {
        assert_name(name)?;
        let raw = self
            .read_raw(name)?
            .ok_or_else(|| anyhow!("snippet '{name}' not found"))?;
        let (fm, body) =
            parse(&raw).with_context(|| format!("parsing frontmatter for snippet '{name}'"))?;
        Ok(Snippet {
            name: name.to_string(),
            frontmatter: fm,
            body,
        })
    }

    pub fn save(&self, input: SaveInput) -> Result<Snippet> {
        assert_name(&input.name)?;
        let _guard = self
            .write_lock
            .lock()
            .map_err(|_| anyhow!("write lock poisoned"))?;

        if !input.overwrite.unwrap_or(false) && self.read_raw(&input.name)?.is_some() {
            bail!(
                "snippet '{}' already exists (pass overwrite:true to replace)",
                input.name
            );
        }
        let fm = Frontmatter {
            description: required_non_empty(&input.description, "description")?,
            args: input.args,
            tags: input.tags,
            kind: Some(input.kind.unwrap_or(SnippetKind::Code)),
            integrations: input.integrations,
        };
        let body = input.body.trim_end_matches('\n').to_string();
        self.write_raw(&input.name, Some(serialize(&fm, &body)?))?;
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
            integrations: input.integrations.or(current.frontmatter.integrations),
            overwrite: Some(true),
        };
        drop(_guard); // save() takes the lock itself
        self.save(next)
    }

    pub fn delete(&self, name: &str) -> Result<()> {
        assert_name(name)?;
        let _guard = self
            .write_lock
            .lock()
            .map_err(|_| anyhow!("write lock poisoned"))?;
        if self.read_raw(name)?.is_none() {
            bail!("deleting snippet '{name}': not found");
        }
        self.write_raw(name, None)
    }

    fn names(&self) -> Result<Vec<String>> {
        let names: Vec<String> = if self.identity.is_some() {
            self.read_bundle()?.into_keys().collect()
        } else {
            self.ensure_dir().context("creating snippets dir")?;
            fs::read_dir(&self.dir)
                .context("reading snippets dir")?
                .filter_map(|e| e.ok()?.file_name().into_string().ok())
                .filter_map(|n| n.strip_suffix(".md").map(str::to_string))
                .collect()
        };
        Ok(names.into_iter().filter(|n| NAME_RE.is_match(n)).collect())
    }

    fn read_raw(&self, name: &str) -> Result<Option<String>> {
        if self.identity.is_some() {
            return Ok(self.read_bundle()?.remove(name));
        }
        let path = self.dir.join(format!("{name}.md"));
        match fs::read_to_string(&path) {
            Ok(s) => Ok(Some(s)),
            Err(e) if e.kind() == ErrorKind::NotFound => Ok(None),
            Err(e) => Err(e).with_context(|| format!("reading {}", path.display())),
        }
    }

    /// Writes (`Some`) or removes (`None`) one snippet. Caller holds the write lock.
    fn write_raw(&self, name: &str, raw: Option<String>) -> Result<()> {
        self.ensure_dir().context("creating snippets dir")?;
        let Some(identity) = &self.identity else {
            let path = self.dir.join(format!("{name}.md"));
            return match raw {
                Some(raw) => atomic_write(&path, raw.as_bytes()),
                None => fs::remove_file(&path),
            }
            .with_context(|| format!("writing {}", path.display()));
        };
        let mut bundle = self.read_bundle()?;
        match raw {
            Some(raw) => bundle.insert(name.to_string(), raw),
            None => bundle.remove(name),
        };
        let json = serde_json::to_vec_pretty(&bundle)?;
        let bytes = age::encrypt(&identity.to_public(), &json).context("encrypting snippets")?;
        atomic_write(&self.dir.join(BUNDLE), &bytes).context("writing snippets bundle")
    }

    fn read_bundle(&self) -> Result<BTreeMap<String, String>> {
        let Some(identity) = &self.identity else {
            bail!("internal error: no identity for snippets bundle");
        };
        let bytes = match fs::read(self.dir.join(BUNDLE)) {
            Ok(b) => b,
            Err(e) if e.kind() == ErrorKind::NotFound => return Ok(BTreeMap::new()),
            Err(e) => return Err(e).context("reading snippets bundle"),
        };
        let json = age::decrypt(identity, &bytes).context("decrypting snippets bundle")?;
        serde_json::from_slice(&json).context("parsing snippets bundle")
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

fn atomic_write(path: &Path, bytes: &[u8]) -> io::Result<()> {
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypted_round_trip() {
        let dir = std::env::temp_dir().join(format!("snippet-mcp-test-{}", std::process::id()));
        let reg = Registry::new(dir.clone(), Some(age::x25519::Identity::generate()));
        reg.save(SaveInput {
            name: "secret_thing".into(),
            description: "d".into(),
            body: "hunter2".into(),
            args: None,
            tags: None,
            kind: None,
            integrations: None,
            overwrite: None,
        })
        .unwrap();
        let on_disk = fs::read(dir.join(BUNDLE)).unwrap();
        assert!(!String::from_utf8_lossy(&on_disk).contains("hunter2"));
        assert!(!String::from_utf8_lossy(&on_disk).contains("secret_thing"));
        assert_eq!(reg.list().unwrap()[0].body, "hunter2\n");
        reg.delete("secret_thing").unwrap();
        assert!(reg.list().unwrap().is_empty());
        fs::remove_dir_all(dir).unwrap();
    }
}
