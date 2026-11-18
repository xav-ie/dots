# Rex

Rex is a terminal multiplexer that is also a native Mac terminal. Rex.app runs a
**server** that owns your **sessions**. A session holds **tabs**, a tab holds
**panes** (Rex's CLI and API call them "blocks"), and a pane can be **floated**
over the layout. Closing the window doesn't end anything: sessions live in the
server until you close them, like tmux, but with no prefix key needed.

Docs: <https://www.superlogical.com/rex/docs/> · Every action, searchable:
`shift+cmd+p` (command palette).

## Cheat sheet

Keys are written the way `init.lua` spells them. ★ = from this repo's
`init.lua`; everything else is a Rex default.

### Sessions & windows

| Key           | Does                                             |
| ------------- | ------------------------------------------------ |
| `cmd+k`       | Session picker (switch session)                  |
| `cmd+p`       | Go to anything: tree of sessions, tabs and panes |
| `shift+cmd+n` | New session                                      |
| `cmd+r`       | Refresh session list                             |
| `cmd+n`       | New window                                       |
| `shift+cmd+w` | Close window                                     |
| `ctrl+cmd+f`  | Toggle full screen                               |
| `shift+cmd+p` | Command palette                                  |

### Tabs

| Key                              | Does                  |
| -------------------------------- | --------------------- |
| `cmd+t`                          | New tab               |
| `alt+cmd+w`                      | Close tab             |
| `ctrl+tab` / `shift+cmd+]`       | Next tab              |
| `ctrl+shift+tab` / `shift+cmd+[` | Previous tab          |
| `cmd+1` … `cmd+8`                | Go to tab 1…8         |
| `cmd+9`                          | Go to last tab        |
| `ctrl+shift+pageup` / `pagedown` | Move tab left / right |

### Panes

| Key                               | Does                                    |
| --------------------------------- | --------------------------------------- |
| `cmd+d` / `shift+cmd+right`       | Split right                             |
| `shift+cmd+d` / `shift+cmd+down`  | Split down                              |
| `shift+cmd+left` / `shift+cmd+up` | Split left / up                         |
| `cmd+enter`                       | Split along the longer side             |
| `alt+cmd+arrow`                   | Focus pane in that direction            |
| `cmd+]` / `cmd+[`                 | Focus next / previous pane              |
| `alt+shift+cmd+arrow`             | Move pane in that direction             |
| `shift+cmd+enter`                 | Zoom pane                               |
| `cmd+w`                           | Close pane                              |
| `alt+cmd+enter`                   | Float pane over the layout              |
| `alt+cmd+m`                       | Minimize / restore the floating window  |
| `alt+shift+cmd+enter`             | Minimize / restore all floating windows |

### Shell & scrollback

| Key                      | Does                                 |
| ------------------------ | ------------------------------------ |
| `cmd+up` / `cmd+down`    | Jump to previous / next shell prompt |
| `cmd+left` / `cmd+right` | Start / end of the input line        |
| `alt+left` / `alt+right` | Word left / right                    |
| `cmd+backspace`          | Clear the input line                 |
| `ctrl+cmd+i`             | Insert a path                        |
| `cmd+f`                  | Find                                 |
| `cmd+g` / `shift+cmd+g`  | Next / previous match                |
| `cmd+y`                  | Quick Look the links on screen       |

### Copy mode (vi keys, `shift+cmd+c` to enter)

| Key                                   | Does                                            |
| ------------------------------------- | ----------------------------------------------- |
| `h j k l` / arrows                    | Move                                            |
| `w b e`, `W B E`                      | Word / WORD motions                             |
| `0` `^` `$`                           | Line start / first non-blank / end              |
| `H M L`                               | Screen top / middle / bottom                    |
| `ctrl+u` `ctrl+d` · `ctrl+b` `ctrl+f` | Half page / page up · down                      |
| `g` / `G` · `{` / `}`                 | History top / bottom · paragraph back / forward |
| `f F t T`, `;` `,`                    | Find character in line, repeat                  |
| `/` `?`, `n` `N`                      | Search forward / backward, next / previous      |
| `v` / `V` / `ctrl+v`                  | Select char / line / block                      |
| `o`                                   | Swap selection ends                             |
| `y` or `enter`                        | Yank selection and exit                         |
| `D`                                   | Yank to end of line                             |
| `1`–`9`                               | Count prefix                                    |
| `esc` or `q`                          | Exit                                            |

### Font & UI

| Key                             | Does                          |
| ------------------------------- | ----------------------------- |
| `cmd+=` / `shift+cmd+=`         | Bigger font                   |
| ★ `ctrl+shift+=` (ctrl+plus)    | Bigger font (from Ghostty)    |
| `cmd+-` · ★ `ctrl+-`            | Smaller font (★ from Ghostty) |
| `cmd+0`                         | Reset font size               |
| `cmd+/`                         | Toggle sidebar                |
| `cmd+.`                         | Toggle activity sidebar       |
| `shift+cmd+s`                   | Toggle toolbar layout         |
| `alt+cmd+t` / `alt+shift+cmd+t` | Peek toolbar / pane header    |
| `cmd+,` / `shift+cmd+,`         | Settings / Diagnostics        |
| `shift+cmd+.`                   | Dismiss a notice              |
| `shift+cmd+u`                   | Install a waiting update      |

## Guide

### Config: `init.lua` in this directory

`~/.config/rex/init.lua` is an out-of-store symlink to `./init.lua`, so edit it
here and choose **Reload Config** (palette) or run `rex config reload`. No
rebuild needed. Check before reloading:

```sh
rex config check   # parse errors and warnings
rex keymap         # what every key does now, and where it was bound
```

Binding syntax (modifiers in the order ctrl, alt, shift, cmd; shifted symbols
are `shift+` the unshifted key, so `+` is `shift+=`):

```lua
rex.bind("cmd+d", "pane.split", { direction = "right" })  -- key -> action
rex.unbind("cmd+k")                                       -- drop a default
rex.bind("ctrl+a>c", "client.tab.new")                    -- sequence (tmux-style prefix)
rex.bind("ctrl+a>ctrl+a", "pane.send_key", { key = "ctrl+a" })  -- still send the prefix

-- Modes: keys that only apply while the mode is on
rex.bind("ctrl+a>r", "client.mode.enter", { name = "resize" })
rex.bind("resize/h", "pane.resize", { direction = "left" })
rex.bind("resize/esc", "client.mode.exit")

-- Custom actions: anything Lua can do, then bind it like a built-in
rex.action{
  name = "git.status", title = "Git Status",
  run = function(ctx, args) rex.exec{ "git", "status" } end,
}
```

All action names: the palette, `rex actions`, or the Mac Actions reference.

### The CLI

`rex` is on PATH everywhere (pinned by the flake); inside Rex the app's own
copy wins via `$REX_BIN_DIR`.

| Command                                       | Does                                                 |
| --------------------------------------------- | ---------------------------------------------------- |
| `rex ls` / `rex new` / `rex kill`             | List / create / kill sessions                        |
| `rex split`, `rex run CMD`                    | Split the focused pane / run a command in a new pane |
| `rex send`, `rex send-key`                    | Type into a terminal                                 |
| `rex capture`                                 | Print a terminal's screen and scrollback             |
| `rex focus`, `zoom`, `move`, `swap`, `resize` | Layout from scripts                                  |
| `rex do ACTION` / `rex do script.lua`         | Run any action or a Lua script                       |
| `rex events`                                  | Stream what's happening (for scripts)                |
| `rex fwd`                                     | Forward TCP ports                                    |

### Agents

Claude Code, Codex, OpenCode and Pi get the `rex` skill, so they can open
tabs, split panes and read other terminals for you. Claude and Codex also run a
SessionStart hook that tells them which Rex session they're in. `rex skill
status` shows Claude's hook as "missing" because it only looks in
`~/.claude/settings.json`; the hook lives in managed settings, the only
place `allowManagedHooksOnly` lets hooks run.

### What's declared where

| Thing                                                                                                                               | Where                                                                        |
| ----------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| rex CLI, `xterm-rex` terminfo, ssh guard                                                                                            | `rex.nix` → upstream `programs.rex` (flake input `rex`)                      |
| Keybindings                                                                                                                         | `init.lua` (live symlink)                                                    |
| Agent skill, Codex hook                                                                                                             | `rex.nix` → `agents/`                                                        |
| Claude hook                                                                                                                         | `modules/claude/managed-settings.json`                                       |
| Settings window: font (Maple Mono NF 13), startup shell (nu), copy on select, themes, cursor shader, agent session naming, updates… | `rex.nix` → `rexDefaults` activation (overwrites Settings UI on each switch) |
| Rex.app itself                                                                                                                      | Not declarative: installed by hand, updates itself                           |

Don't run `rex skill setup` or `rex terminfo setup`. Everything they do is
declared here, and `skill setup` would write the Claude hook back into
`settings.json`, which is a live symlink into this repo.

Changing a setting in the Settings window works until the next switch, which
resets it. To keep it, find its key (`defaults export com.superlogical.rex -`
before and after, then diff) and add it to `rexDefaults`. Toggling
**agent session naming** also makes Rex.app re-run `rex skill setup`: it
rewrites the skill files (the next switch restores them) and adds the Claude
hook to `settings.json` (revert that with `git checkout`). If you turn naming
off, add `--feature-session-naming=false` back to `agents/SKILL.md`,
`agents/codex-hooks.json` and the hook in `managed-settings.json`.
