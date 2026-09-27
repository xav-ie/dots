#!/usr/bin/env -S nu --stdin

# Suggests executor tools/snippets whose embedding closely matches what was
# just said: the user's prompt (UserPromptSubmit) or the agent's latest text
# (PostToolBatch, read from the transcript tail). Plan and threshold
# calibration: ~/Projects/snippet-evals/SUGGESTIONS_PLAN.md.
#
# Log-only unless CLAUDE_TOOL_SUGGEST=inject: every run appends a line to
# ~/.local/state/claude-tool-suggest/suggestions.jsonl (hash + length of the
# text, never the text itself). Any failure (no embed service, no executor,
# no token: e.g. on nox) exits 0 silently.
#
# Knobs (env): CLAUDE_TOOL_SUGGEST (log | inject | off), _THRESHOLD (cosine,
# default 0.67 for harrier-oss-v1-0.6b), _EMBED_URL, _EXECUTOR_URL.

use ~/.claude/lib-transcript.nu last-assistant-text

const INSTRUCT = "Instruct: Given a user request, retrieve the tool that can fulfill it\nQuery: "
const CACHE = "~/.cache/claude-tool-suggest"
const LOG = "~/.local/state/claude-tool-suggest/suggestions.jsonl"
const CATALOG_TTL = 10min
const MAX_SUGGEST = 3

def cfg [] {
  {
    mode: ($env.CLAUDE_TOOL_SUGGEST? | default "log")
    threshold: ($env.CLAUDE_TOOL_SUGGEST_THRESHOLD? | default "0.67" | into float)
    embed: (
      $env.CLAUDE_TOOL_SUGGEST_EMBED_URL?
      | default "http://127.0.0.1:38978/v1/embeddings"
    )
    executor: ($env.CLAUDE_TOOL_SUGGEST_EXECUTOR_URL? | default "http://127.0.0.1:38972")
  }
}

# `integration.name`, so `tools.outsmartly.start_build` and
# `outsmartly.org.outsmartlyoauth.start_build` compare equal.
def short-path [path: string]: nothing -> string {
  let parts = $path | str replace -r '^tools\.' "" | split row "."
  $"($parts | first).($parts | last)"
}

def doc-text [tool: record]: nothing -> string {
  let desc = $tool.description | str substring 0..1999
  $"($tool.path)\n($tool.name | str replace -a '_' ' ')\n($desc)"
}

def normalize [v: list<float>]: nothing -> list<float> {
  let norm = $v | each {|x| $x * $x } | math sum | math sqrt
  $v | each {|x| $x / $norm }
}

def embed [cfg: record, texts: list<string>, --timeout: duration]: nothing -> list<any> {

  # Default set here, not in the signature: the nu formatter rewrites a
  # `= 1sec` flag default to `= sec`.
  let timeout = $timeout | default 1sec
  http post --content-type application/json --max-time $timeout $cfg.embed {input: $texts}
  | get data
  | sort-by index
  | each {|d| normalize $d.embedding }
}

def catalog [cfg: record]: nothing -> list<any> {
  let file = $CACHE | path expand | path join catalog.json
  let fresh = ($file | path exists) and ((date now) - (ls $file | first | get modified) < $CATALOG_TTL)
  if $fresh { return (open $file) }
  let fetched = try {
    http get --max-time 2sec --headers [Authorization $"Bearer ($env.EXECUTOR_AUTH_TOKEN)"] $"($cfg.executor)/api/tools"
    | each {|t| {path: ($t.address | str replace -r '^tools\.' ""), name: $t.name, description: ($t.description? | default "")} }
  } catch { null }
  if $fetched == null {
    # Keep serving a stale catalogue rather than going dark on a hiccup.
    if ($file | path exists) { return (open $file) }
    error make {msg: "no catalogue"}
  }
  mkdir ($file | path dirname)
  $fetched | to json -r | save -f $file
  $fetched
}

# Cache key: the embed endpoint (stands in for the model) plus every doc text.
def vectors-file [cfg: record, texts: list<string>]: nothing -> string {
  let key = [$cfg.embed ...$texts] | str join (char nl) | hash sha256 | str substring 0..15
  $CACHE | path expand | path join $"vectors-($key).json"
}

# Doc vectors for this exact catalogue, or null while they are being built.
# Embedding ~400 docs can outlast the hook timeout, so a miss hands the work to
# a detached `build` run and this prompt goes without suggestions.
def doc-vectors [cfg: record, texts: list<string>]: nothing -> any {
  let file = vectors-file $cfg $texts
  if ($file | path exists) { return (open $file) }
  let lock = $CACHE | path expand | path join "build.lock"
  let building = ($lock | path exists) and ((date now) - (ls $lock | first | get modified) < 2min)
  if not $building {
    mkdir ($lock | path dirname)
    touch $lock
    let cmd = $"setsid -f '($nu.current-exe)' '($env.CURRENT_FILE)' build </dev/null >/dev/null 2>&1"
    ^sh -c $cmd
  }
  null
}

# Executor tools this session already called, from the raw transcript.
def used-tools [transcript: string]: nothing -> list<string> {
  if ($transcript | is-empty) or not ($transcript | path exists) { return [] }
  open --raw $transcript
  | parse -r 'tools\.((?:[a-z_]+)(?:\.[A-Za-z0-9_]+)+)'
  | get capture0
  | uniq
  | each {|p| short-path $p }
  | uniq
}

def suggest [input: record] {
  let cfg = cfg
  if $cfg.mode == "off" or ($env.EXECUTOR_AUTH_TOKEN? | is-empty) { return }
  let event = $input.hook_event_name? | default ""
  let text = (match $event {
    "UserPromptSubmit" => ($input.prompt? | default "")
    "PostToolBatch" => (last-assistant-text ($input.transcript_path? | default ""))
    _ => ""
  }) | str trim
  if ($text | str length) < 8 { return }

  let tools = catalog $cfg
  let vectors = doc-vectors $cfg ($tools | each {|t| doc-text $t })
  if $vectors == null { return }
  let q = embed $cfg [
    ($INSTRUCT + ($text | str substring 0..1999))
  ] | first

  let ranked = $tools | zip $vectors | par-each {|pair|
    {path: $pair.0.path, description: $pair.0.description, score: ($pair.1 | zip $q | each {|p| $p.0 * $p.1 } | math sum)}
  } | sort-by score -r

  let sid = $input.session_id? | default "unknown"
  let state = $CACHE | path expand | path join sessions $"($sid).json"
  let suggested = if ($state | path exists) { open $state } else { [] }
  let skip = $suggested ++ (used-tools ($input.transcript_path? | default ""))
  let picks = $ranked
  | where score >= $cfg.threshold
  | where {|r| (short-path $r.path) not-in $skip }
  | first $MAX_SUGGEST

  mkdir ($state | path dirname)
  $suggested ++ ($picks | each {|p| short-path $p.path }) | to json -r | save -f $state

  let log = $LOG | path expand
  mkdir ($log | path dirname)
  {
    ts: (date now | format date "%+")
    session_id: $sid
    event: $event
    mode: $cfg.mode
    text_sha: ($text | hash sha256)
    text_len: ($text | str length)
    top: (
      $ranked
      | first 5
      | each {|r| {path: $r.path, score: ($r.score | math round -p 4)} }
    )
    would_inject: ($picks | get path)
  } | to json -r | $in + "\n" | save --append $log

  if $cfg.mode != "inject" or ($picks | is-empty) { return }
  let lines = $picks | each {|p|
    let summary = $p.description | lines | get 0? | default "" | str substring 0..139
    $"- tools.($p.path): ($summary)"
  }
  {
    hookSpecificOutput: {
      hookEventName: $event
      additionalContext: (
        [
          "Possibly relevant executor tools (optional, use only if they fit the task):"
        ] ++ $lines
        | str join (char nl)
      )
    }
  } | to json -r | print
}

def main [] {
  let raw = $in
  try { suggest ($raw | from json) }
  exit 0
}

# Detached: embed the current catalogue's docs into the vector cache.
def "main build" [] {
  let lock = $CACHE | path expand | path join "build.lock"
  try {
    let cfg = cfg
    let texts = catalog $cfg | each {|t| doc-text $t }
    let file = vectors-file $cfg $texts
    let vectors = $texts | chunks 32 | each {|batch| embed $cfg $batch --timeout 60sec } | flatten
    $vectors | each {|v| $v | each {|x| $x | math round -p 5 } } | to json -r | save -f $"($file).tmp"
    mv -f $"($file).tmp" $file
  }
  rm -f $lock
}

# `~/.claude/tool-suggest.nu selftest`: helpers that dedupe and score rely on.
def "main selftest" [] {
  use std/assert
  assert equal (short-path "tools.outsmartly.start_build") "outsmartly.start_build"
  assert equal (short-path "outsmartly.org.outsmartlyoauth.start_build") "outsmartly.start_build"
  assert equal (short-path "tools.snippets.org.workspace.mail_search_read") "snippets.mail_search_read"
  assert equal (normalize [3.0 4.0]) [0.6 0.8]
  print "ok"
}
