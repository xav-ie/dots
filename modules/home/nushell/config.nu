# Nushell Config File
#
# config.nu is commonly used to:
# - Set environment variables for Nushell and other applications
# - Set Nushell settings in $env.config
# - Load modules or source files so that their commands are readily available
# - Run any other applications or commands at startup
#
# version = "0.96.1"

$env.config.color_config.search_result = { bg: "#dd2200" fg: white }

# claude-sessions: resumable sessions for the current dir, newest first.
# Claude stores one <uuid>.jsonl per session under
# ~/.claude/projects/<cwd-with-every-non-alnum-as-dash>/. We surface the
# generated title + latest prompt + mtime as the *display*, while the value
# inserted is the bare session id (see the completer below).
def claude-sessions [] {
  let base = ($env.CLAUDE_CONFIG_DIR? | default ([$env.HOME ".claude"] | path join)) | path join "projects"
  let dir = ([$base (pwd | str replace -ra '[^a-zA-Z0-9]' '-')] | path join)
  if not ($dir | path exists) { return [] }
  let files = (ls ($"($dir)/*.jsonl" | into glob) | sort-by modified -r)
  # One ripgrep pass pulls just the two small marker line-types out of every
  # transcript (cheaper than parsing the multi-MB files), grouped by file.
  # -g '*.jsonl' keeps rg from recursing into sibling files (e.g. a memory/
  # dir whose notes mention these very type strings); the per-line guard means
  # any stray non-record match is skipped rather than killing completion.
  let hits = (rg -N --no-heading -H -g '*.jsonl' '"type":"(ai-title|last-prompt)"' $dir
    | lines
    | parse --regex '^(?<f>[^:]+):(?<j>.+)$'
    | each {|r|
        let o = (try { $r.j | from json } catch { {} })
        let t = ($o.type? | default "")
        if $t in ["ai-title" "last-prompt"] {
          { f: ($r.f | path basename), kind: $t
            text: (if $t == "ai-title" { $o.aiTitle? | default "" } else { $o.lastPrompt? | default "" }) }
        }
      }
    | compact
    | group-by f)
  # Precompute the ANSI codes once: datetime + title are colored distinctly
  # from the dimmed last-message "description". display_override keeps the raw
  # codes (nushell doesn't strip them there) and the terminal renders them.
  let col = { time: (ansi cyan), title: (ansi green_bold), desc: (ansi dark_gray), reset: (ansi reset) }
  $files | each {|file|
    let key = ($file.name | path basename)
    let rows = ($hits | get -o $key | default [])
    let titles = ($rows | where kind == "ai-title" | get text)
    let lasts  = ($rows | where kind == "last-prompt" | get text)
    let title = (if ($titles | is-empty) { "(untitled)" } else { $titles | last })
    let last  = (if ($lasts | is-empty) { "" } else { $lasts | last | str replace -ra '\s+' ' ' | str substring 0..80 })
    let date  = ($file.modified | format date '%m-%d %H:%M')
    let disp = $"($col.time)($date)($col.reset)  ($col.title)($title)($col.reset)  ($col.desc)($last)($col.reset)"
    { value: ($key | str replace '.jsonl' ''), display_override: $disp }
  }
}

let carapace_completer = {|spans|
  # `claude --resume <id>` / `-r <id>`: serve our own session list. carapace
  # force-sorts alphabetically and can only show the inserted value (the uuid),
  # so we return records with display_override (title shown, id inserted). The
  # config external completer must return a *plain list* — a {completions,
  # options} record is rejected as invalid (that form is only for `@`-attached
  # completers) — and it preserves list order, so claude-sessions' newest-first
  # ordering is what the menu shows.
  if $spans.0 == "claude" and ($spans | length) >= 2 and (($spans | get (($spans | length) - 2)) in ["-r" "--resume"]) {
    claude-sessions
  } else {
    carapace $spans.0 nushell ...$spans | from json
  }
}
$env.config.completions.external = {
  # set to false to prevent nushell looking into $env.PATH to find more
  # suggestions, `false` recommended for WSL users as this look up may be
  # very slow
  enable: true
  # setting it lower can improve completion performance at the cost of
  # omitting some options
  max_results: 100
  completer: $carapace_completer
}

$env.config.cursor_shape = {
  # block, underscore, line, blink_block, blink_underscore, blink_line,
  # inherit to skip setting cursor shape (line is the default)
  emacs: line
  # block, underscore, line, blink_block, blink_underscore, blink_line,
  # inherit to skip setting cursor shape (block is the default)
  vi_insert: line
  # block, underscore, line, blink_block, blink_underscore, blink_line,
  # inherit to skip setting cursor shape (underscore is the default)
  vi_normal: blink_block
}

$env.config.edit_mode = "vi" # emacs, vi

$env.config.explore = {
  status_bar_background: { fg: white, bg: black },
  command_bar_text: { fg: "#C4C9C6" },
  highlight: { fg: "black", bg: "yellow" },
  status: {
    error: { fg: "white", bg: "red" },
    warn: {}
    info: {}
  },
  selected_cell: { bg: light_blue },
}

$env.config.hooks.pre_execution = [
  { || if 'TMUX_PANE' in $env { $env.TMUX_TAB_UPDATE_PANE = $env.TMUX_PANE } }
]


# tmux-tab-name-update only matters when $PWD changes (tab name is derived
# from directory + git branch).  Move from pre_prompt (every prompt) to
# env_change.PWD (only on cd) — saves ~2ms per non-cd prompt.
#
# Tradeoff: if you `git checkout other-branch` without cd, the tab name
# keeps showing the old branch until the next cd.  `cd .` refreshes.
$env.config.hooks.env_change = ($env.config.hooks.env_change? | default {})
$env.config.hooks.env_change.PWD = (
    $env.config.hooks.env_change.PWD?
    | default []
    | append { |_before, _after| tmux-tab-name-update }
)

# --- graphical session env ---------------------------------------------------
# Pull the live graphical session's compositor vars (DISPLAY, WAYLAND_DISPLAY, …)
# into the current shell. Use it to un-stick a tmux pane that was started over
# SSH so firefox-router / xdg-open can reach the display. Only *sets* vars —
# clearing them again (to go headless) is left to you.
#
# Source is `systemctl --user show-environment`, the canonical graphical session
# Hyprland imports its env into. New panes opened after a local `tmux attach`
# already inherit these via update-environment (../tmux.nix); this is for
# already-running shells.
def --env get-graphical-env [] {
  systemctl --user show-environment
  | lines
  | parse "{name}={value}"
  | where name in [DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XAUTHORITY]
  | reduce -f {} {|it, acc| $acc | insert $it.name $it.value }
  | load-env
}

$env.config.keybindings ++= [
  {
    name: cut_line_from_start
    modifier: control
    keycode: char_u
    mode: [emacs, vi_insert]
    event: { edit: cutfromstart }
  }
]

# true or false to enable or disable right prompt to be rendered on last line
# of the prompt.
$env.config.render_right_prompt_on_last_line = false

$env.config.show_banner = false

$env.config.table = {
  # basic, compact, compact_double, light, thin, with_love, rounded,
  # reinforced, heavy, none, other
  mode: compact
  # "always" show indexes, "never" show indexes, "auto" = show indexes when a
  # table has "index" column
  index_mode: always
  # show 'empty list' and 'empty record' placeholders for command output
  show_empty: true
  # a left right padding of each column in a table
  padding: { left: 1, right: 1 }
  trim: {
    # wrapping or truncating
    methodology: wrapping
    # A strategy used by the 'wrapping' methodology
    wrapping_try_keep_words: true
    # A suffix used by the 'truncating' methodology
    truncating_suffix: "..."
  }
  # show header text on separator/border line
  header_on_separator: false
  # # limit data rows from top and bottom after reaching a set point
  # abbreviated_row_count: 10
}

# --- zoxide commands ---------------------------------------------------------
# We own `z`/`zi`/`zf` here because programs.zoxide is set with `--no-cmd`
# (see home-manager/default.nix): that keeps zoxide's directory-tracking hook
# but drops its auto-generated aliases, which load *after* this file and would
# otherwise shadow these defs. All three only ever *read* the db.

# zf: fuzzy zoxide jump via skim.
#
# Why this exists: zoxide's own matcher is *substring*, so a query like `xnxi`
# never matches `xnixvim`. Here we feed the FULL db (`zoxide query --list`,
# already ranked by frecency) straight into skim and let skim fuzzy-match —
# that's what makes typos forgiving.
def --env --wrapped zf [...rest: string] {
  let sel = (
    zoxide query --list
    | sk --query ($rest | str join ' ') --height 40% --layout reverse --prompt "z> "
    | str trim
  )
  if ($sel | is-not-empty) { cd $sel }
}

# zi: interactive picker over the whole db — same as `zf` with no/seed query.
def --env --wrapped zi [...rest: string] {
  zf ...$rest
}

# z: zoxide jump. On a miss, fall through to `zf` so a typo opens the skim
# picker (seeded with your keywords) instead of just erroring. No db writes.
def --env --wrapped z [...rest: string] {
  let path = match $rest {
    [] => {'~'},
    [ '-' ] => {'-'},
    [ $arg ] if ($arg | path expand | path type) == 'dir' => {$arg}
    _ => {
      # `do {...} | complete` captures the exit code and swallows zoxide's
      # "no match found" stderr instead of aborting on a miss.
      (do { zoxide query --exclude $env.PWD -- ...$rest } | complete).stdout
      | str trim -r -c "\n"
    }
  }
  if ($path | is-empty) {
    zf ...$rest
  } else {
    cd $path
  }
}

# gcot: git checkout tag — tab-completes only tags, with <base>latest alias
# for the most recent tag per prefix. Resolves *latest at checkout time.
def "nu-complete git tags" [context: string] {
  let token = ($context | split row " " | last)
  let recent = (^git tag --sort=-creatordate | lines | where {|x| $x != ""})
  let matches = ($recent | where {|t| $t | str starts-with $token})
  let normal  = ($matches | each {|t| { value: $t, description: "" } })
  mut bases = ($matches
    | each {|t| if ($t | str contains "@") { ($t | split row "@" | first) + "@" } }
    | compact | uniq)
  for p in ["latest" "lates" "late" "lat" "la" "l"] {
    if ($token | str ends-with $p) {
      $bases = ($bases | append ($token | str substring 0..<(($token | str length) - ($p | str length))))
      break
    }
  }
  $bases = ($bases | where {|b| $b != ""} | uniq)
  let latest = ($bases | each {|b|
      let real = ($recent | where {|t| $t | str starts-with $b} | first)
      let alias = $"($b)latest"
      if ($real != null) and (($alias | str starts-with $token) or ($token | str starts-with $alias)) {
        { value: $alias, description: $"→ ($real)" }
      }
    } | compact)
  {
    options: { filter: false, sort: false }
    completions: ($latest | append $normal | uniq-by value)
  }
}

def gcot [tag: string@"nu-complete git tags"] {
  let resolved = if ($tag | str ends-with "latest") {
    let base = ($tag | str substring 0..<(($tag | str length) - 6))
    ^git tag --sort=-creatordate --list $"($base)*" | lines | where {|x| $x != ""} | first
      | default $tag
  } else { $tag }
  git checkout $resolved
}

