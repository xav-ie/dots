//! Nushell plugin that renders the prompt in-process — no subprocess fork
//! per prompt, no separate daemon.  The plugin process is spawned once by
//! nushell and persists for the shell's lifetime.
//!
//! Per-prompt cost is the plugin protocol IPC (~0.1-0.3ms msgpack roundtrip)
//! plus the actual render (~0.1ms in $HOME, ~1-3ms in a typical git repo
//! from the gix status walk).

use std::path::Path;

use nu_plugin::{
    EngineInterface, EvaluatedCall, MsgPackSerializer, Plugin, PluginCommand, SimplePluginCommand,
    serve_plugin,
};
use nu_protocol::{Category, LabeledError, Signature, Value};

// ---------- Plugin scaffolding ----------

struct PromptPlugin;

impl Plugin for PromptPlugin {
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").into()
    }

    fn commands(&self) -> Vec<Box<dyn PluginCommand<Plugin = Self>>> {
        vec![Box::new(PromptRender)]
    }
}

// ---------- The single command ----------

struct PromptRender;

impl SimplePluginCommand for PromptRender {
    type Plugin = PromptPlugin;

    fn name(&self) -> &str {
        "prompt-render"
    }

    fn description(&self) -> &str {
        "Render the prompt for the current working directory."
    }

    fn signature(&self) -> Signature {
        Signature::build(PluginCommand::name(self))
            .input_output_type(nu_protocol::Type::Nothing, nu_protocol::Type::String)
            .category(Category::Custom("prompt".into()))
    }

    fn run(
        &self,
        _plugin: &Self::Plugin,
        engine: &EngineInterface,
        call: &EvaluatedCall,
        _input: &Value,
    ) -> Result<Value, LabeledError> {
        let pwd_string = engine
            .get_env_var("PWD")
            .map_err(|e| LabeledError::new(e.to_string()))?
            .ok_or_else(|| LabeledError::new("PWD env var not set"))?
            .coerce_into_string()
            .map_err(|e| LabeledError::new(e.to_string()))?;
        let pwd = Path::new(&pwd_string);
        let s = render(pwd);
        Ok(Value::string(s, call.head))
    }
}

// ---------- Render ----------

fn render(pwd: &Path) -> String {
    let repo = gix::discover(pwd).ok();
    let dir = render_dir(pwd, repo.as_ref());
    let branch = repo.as_ref().and_then(git_branch);
    let dirty = repo.as_ref().and_then(compute_git_status);

    let mut s = String::with_capacity(96);
    s.push_str("\x1b[1;36m"); // bold cyan
    s.push_str(&dir);
    s.push_str("\x1b[0m");
    if let Some(b) = branch {
        s.push_str(" \x1b[1;35mon \u{e0a0} ");
        s.push_str(&b);
        s.push_str("\x1b[0m");
        if let Some(d) = dirty {
            s.push_str(" \x1b[1;31m[");
            s.push_str(&d);
            s.push_str("]\x1b[0m");
        }
    }
    // Trailing newline so the indicator lands on its own line.
    s.push('\n');
    s
}

fn render_dir(pwd: &Path, repo: Option<&gix::Repository>) -> String {
    if let Some(r) = repo
        && let Some(workdir) = r.workdir()
        && let Some(parent) = workdir.parent()
        && let Ok(rel) = pwd.strip_prefix(parent)
    {
        // keep_first=true preserves the repo basename as the anchor, so a
        // deep subdir reads as `repo/…/leaf` instead of `…/leaf`.
        return cap_components(&rel.to_string_lossy(), 3, true);
    }
    truncate_dir(pwd, 3)
}

fn truncate_dir(pwd: &Path, keep: usize) -> String {
    let pwd_str = pwd.display().to_string();
    let display = if let Ok(home) = std::env::var("HOME") {
        if pwd_str == home {
            return "~".into();
        }
        if let Some(rest) = pwd_str.strip_prefix(&format!("{home}/")) {
            format!("~/{rest}")
        } else {
            pwd_str
        }
    } else {
        pwd_str
    };
    cap_components(&display, keep, false)
}

/// Keep at most `keep` trailing path components, prefixing `…/` when truncated.
/// When `keep_first`, the first component is preserved as an anchor — useful
/// for repo-relative paths so `repo/a/b/c/d` becomes `repo/…/c/d` (not `…/b/c/d`).
fn cap_components(s: &str, keep: usize, keep_first: bool) -> String {
    let parts: Vec<&str> = s.split('/').filter(|p| !p.is_empty()).collect();
    if parts.len() <= keep {
        return s.to_string();
    }
    if keep_first && keep >= 2 {
        let tail = &parts[parts.len() - (keep - 1)..];
        format!("{}/…/{}", parts[0], tail.join("/"))
    } else {
        let tail = &parts[parts.len() - keep..];
        format!("…/{}", tail.join("/"))
    }
}

fn git_branch(repo: &gix::Repository) -> Option<String> {
    if let Ok(Some(name)) = repo.head_name() {
        return Some(name.shorten().to_string());
    }
    let id = repo.head_id().ok()?;
    Some(id.to_hex_with_len(7).to_string())
}

fn compute_git_status(repo: &gix::Repository) -> Option<String> {
    let mut conflicted = false;
    let mut deleted = false;
    let mut renamed = false;
    let mut modified = false;
    let mut staged = false;
    let mut untracked = false;

    let status_iter = repo
        .status(gix::progress::Discard)
        .ok()?
        .into_iter(None)
        .ok()?;

    for change in status_iter.filter_map(Result::ok) {
        use gix::status::Item;
        match change {
            Item::TreeIndex(c) => {
                use gix::diff::index::Change;
                match c {
                    Change::Addition { .. } | Change::Modification { .. } => staged = true,
                    Change::Deletion { .. } => deleted = true,
                    Change::Rewrite { .. } => renamed = true,
                }
            }
            Item::IndexWorktree(item) => {
                use gix::status::index_worktree::Item as IwItem;
                use gix::status::plumbing::index_as_worktree::{Change, EntryStatus};
                match item {
                    IwItem::Modification {
                        status: EntryStatus::Conflict { .. },
                        ..
                    } => conflicted = true,
                    IwItem::Modification {
                        status: EntryStatus::Change(Change::Removed),
                        ..
                    } => deleted = true,
                    IwItem::Modification {
                        status:
                            EntryStatus::IntentToAdd
                            | EntryStatus::Change(
                                Change::Modification { .. } | Change::SubmoduleModification(_),
                            ),
                        ..
                    } => modified = true,
                    IwItem::DirectoryContents { entry, .. } => {
                        if matches!(entry.status, gix::dir::entry::Status::Untracked) {
                            untracked = true;
                        }
                    }
                    // EntryStatus::Change(Change::Type) => typechanged — no glyph in starship defaults
                    // EntryStatus::NeedsUpdate => not a real change, just a stat refresh hint
                    _ => {}
                }
            }
        }
    }

    let stashed = matches!(repo.try_find_reference("refs/stash"), Ok(Some(_)));
    let (ahead, behind) = ahead_behind(repo).unwrap_or((false, false));

    // Order matches starship's default $all_status$ahead_behind:
    // conflicted, stashed, deleted, renamed, modified, staged, untracked, then ahead/behind/diverged.
    let mut out = String::new();
    if conflicted {
        out.push('=');
    }
    if stashed {
        out.push('$');
    }
    if deleted {
        out.push('✘');
    }
    if renamed {
        out.push('»');
    }
    if modified {
        out.push('!');
    }
    if staged {
        out.push('+');
    }
    if untracked {
        out.push('?');
    }
    match (ahead, behind) {
        (true, true) => out.push('⇕'),
        (true, false) => out.push('⇡'),
        (false, true) => out.push('⇣'),
        (false, false) => {}
    }
    if out.is_empty() { None } else { Some(out) }
}

/// Returns `(ahead, behind)` as booleans — we only need presence, not counts,
/// which lets the rev-walk short-circuit at the first qualifying commit.
fn ahead_behind(repo: &gix::Repository) -> Option<(bool, bool)> {
    let head_ref = repo.head_ref().ok()??;
    let upstream_name = head_ref
        .remote_tracking_ref_name(gix::remote::Direction::Fetch)?
        .ok()?;
    let mut upstream_ref = repo.try_find_reference(upstream_name.as_bstr()).ok()??;
    let upstream_id = upstream_ref.peel_to_id().ok()?.detach();
    let local_id = repo.head_id().ok()?.detach();
    if local_id == upstream_id {
        return Some((false, false));
    }

    let ahead = repo
        .rev_walk([local_id])
        .with_hidden([upstream_id])
        .all()
        .ok()?
        .filter_map(Result::ok)
        .next()
        .is_some();
    let behind = repo
        .rev_walk([upstream_id])
        .with_hidden([local_id])
        .all()
        .ok()?
        .filter_map(Result::ok)
        .next()
        .is_some();
    Some((ahead, behind))
}

// ---------- Entry point ----------

fn main() {
    serve_plugin(&PromptPlugin, MsgPackSerializer);
}
