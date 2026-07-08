#!/usr/bin/env -S nu --stdin

# PostToolUse hook for Edit|Write. Runs prettier on the edited file (if the
# project has a local prettier) and a typecheck on TS edits. Output is filtered
# to errors referencing the edited file, so pre-existing errors in other files
# don't create noise.
#
# Per-project overrides live in .edit-hooks.json (walked up from the edited
# file). See edit-hooks.schema.json for shape. Commands receive the edited
# file's absolute path via the $FILE env var. Without an override, falls back
# to ./node_modules/.bin/tsc --noEmit at the nearest package.json.
#
# Failures exit 2 so Claude sees the error.

const TSC_FAST_THRESHOLD_MS = 10000
const TSC_RETRY_AFTER_SEC = 900  # re-probe slow projects every 15m

def find-up [start: string, target: string]: nothing -> string {
  mut dir = $start
  loop {
    let candidate = ([$dir $target] | path join)
    if ($candidate | path exists) { return $candidate }
    let parent = ($dir | path dirname)
    if $parent == $dir { return "" }
    $dir = $parent
  }
  ""
}

def glob-to-regex [pattern: string]: nothing -> string {
  mut out = ""
  mut i = 0
  let chars = ($pattern | split chars)
  let n = ($chars | length)
  while $i < $n {
    let c = ($chars | get $i)
    let n1 = (if ($i + 1) < $n { $chars | get ($i + 1) } else { "" })
    let n2 = (if ($i + 2) < $n { $chars | get ($i + 2) } else { "" })
    if $c == "*" and $n1 == "*" {
      if $n2 == "/" {
        $out = $out ++ "(?:.*/)?"
        $i = $i + 3
      } else {
        $out = $out ++ ".*"
        $i = $i + 2
      }
    } else if $c == "*" {
      $out = $out ++ "[^/]*"
      $i = $i + 1
    } else if $c == "?" {
      $out = $out ++ "[^/]"
      $i = $i + 1
    } else if $c == "{" {
      mut j = $i + 1
      mut found = false
      while $j < $n {
        if ($chars | get $j) == "}" { $found = true; break }
        $j = $j + 1
      }
      if $found {
        let inner = ($chars | slice ($i + 1)..($j - 1) | str join "")
        let alts = ($inner | split row "," | each {|a| $a | str trim })
        let esc = ($alts | each {|a|
          $a | split chars | each {|ch|
            if $ch in [".", "+", "(", ")", "$", "^", "|", "\\", "[", "]", "*", "?", "{", "}"] { $"\\($ch)" } else { $ch }
          } | str join ""
        })
        $out = $out ++ "(?:" ++ ($esc | str join "|") ++ ")"
        $i = $j + 1
      } else {
        $out = $out ++ '\{'
        $i = $i + 1
      }
    } else if $c in [".", "+", "(", ")", "$", "^", "|", "\\", "[", "]"] {
      $out = $out ++ $"\\($c)"
      $i = $i + 1
    } else {
      $out = $out ++ $c
      $i = $i + 1
    }
  }
  "^" ++ $out ++ "$"
}

def matches-glob [path: string, pattern: string]: nothing -> bool {
  let re = (glob-to-regex $pattern)
  $path =~ $re
}

# Filter typecheck output to error blocks whose header line starts with rel_path.
# A block starts at a non-indented line; continuation lines are indented.
def filter-to-file [output: string, rel_path: string]: nothing -> string {
  mut kept = []
  mut keep_current = false
  for line in ($output | lines) {
    let first = (if ($line | str length) > 0 { $line | str substring 0..<1 } else { " " })
    let is_header = $first != " " and $first != "\t"
    if $is_header {
      $keep_current = ($line | str starts-with $rel_path)
    }
    if $keep_current {
      $kept = ($kept | append $line)
    }
  }
  $kept | str join "\n"
}

def tsc-cache-path [key: string]: nothing -> string {
  let hash = ($key | hash md5)
  let cache_dir = ([$env.HOME ".cache" "claude-format-and-lint"] | path join)
  if not ($cache_dir | path exists) { mkdir $cache_dir }
  [$cache_dir $"($hash).json"] | path join
}

def should-run-tsc [key: string]: nothing -> bool {
  let cache = tsc-cache-path $key
  if not ($cache | path exists) { return true }
  try {
    let data = (open $cache)
    if $data.duration_ms < $TSC_FAST_THRESHOLD_MS { return true }
    let age_sec = ((date now) - ($data.recorded_at | into datetime)) / 1sec
    $age_sec > $TSC_RETRY_AFTER_SEC
  } catch { true }
}

def record-tsc-duration [key: string, duration_ms: int] {
  let cache = tsc-cache-path $key
  {
    duration_ms: $duration_ms
    recorded_at: (date now | format date "%+")
    key: $key
  } | to json | save -f $cache
}

def run-typecheck [
  cwd: string
  command: string
  file_abs: string
  cache_key: string
] {
  if not (should-run-tsc $cache_key) { return }
  let rel_path = (try { $file_abs | path relative-to $cwd } catch { $file_abs })
  cd $cwd
  let start = (date now)
  let result = (with-env { FILE: $file_abs } { ^bash -c $command | complete })
  let duration_ms = (((date now) - $start) / 1ms | into int)
  record-tsc-duration $cache_key $duration_ms
  if $result.exit_code == 0 { return }
  let combined = ([$result.stdout $result.stderr] | where {|s| ($s | str trim) != "" } | str join "\n")
  let filtered = (filter-to-file $combined $rel_path)
  if ($filtered | str trim | is-empty) { return }
  print -e $"typecheck failed for ($rel_path) in ($cwd):"
  print -e $filtered
  exit 2
}

def git-root [start_dir: string]: nothing -> string {
  try {
    let result = (^git -C $start_dir rev-parse --show-toplevel | complete)
    if $result.exit_code == 0 { $result.stdout | str trim } else { "" }
  } catch { "" }
}

def main [] {
  let input = try { $in | from json } catch { return }
  let file_path = try { $input.tool_input.file_path } catch { return }

  if ($file_path | is-empty) { return }
  if not ($file_path | path exists) { return }
  if ($file_path | str contains "/node_modules/") { return }
  if ($file_path | str contains "/.git/") { return }

  let file_abs = ($file_path | path expand)
  let file_dir = ($file_abs | path dirname)

  # Anchor on git root when possible — one .edit-hooks.json per repo at the
  # root. Non-git projects fall back to the nearest package.json.
  let root_from_git = (git-root $file_dir)
  let root = if ($root_from_git | is-not-empty) {
    $root_from_git
  } else {
    let pkg_json = (find-up $file_dir "package.json")
    if ($pkg_json | is-empty) { return }
    $pkg_json | path dirname
  }

  # Prettier at project root, if available
  let prettier_bin = $"($root)/node_modules/.bin/prettier"
  if ($prettier_bin | path exists) {
    do -i { ^$prettier_bin --write --ignore-unknown $file_abs } | ignore
  }

  # Typecheck TS and JS variants (.d.ts has ext="ts" via path parse).
  let ext = ($file_abs | path parse | get extension)
  if not ($ext in ["ts" "tsx" "mts" "cts" "js" "jsx" "mjs" "cjs"]) { return }

  let lint_config = $"($root)/.edit-hooks.json"
  if ($lint_config | path exists) {
    let config = try { open $lint_config } catch { return }
    let rules = try { $config.typecheck } catch { [] }
    let rel_from_root = (try { $file_abs | path relative-to $root } catch { "" })
    if ($rel_from_root | is-empty) { return }
    for rule in $rules {
      if (matches-glob $rel_from_root $rule.match) {
        let cwd = ([$root ($rule.cwd? | default ".")] | path join | path expand)
        run-typecheck $cwd $rule.command $file_abs $root
        return
      }
    }
    # No rule matched — warn so the user adds one. Use "command": "true" to
    # opt out explicitly.
    print -e $"edit-hooks: no typecheck rule matched ($rel_from_root)"
    print -e $"add a rule in ($lint_config), or use \"command\": \"true\" to skip"
    exit 2
  }

  # Fallback: plain tsc --noEmit at repo root
  let tsc_bin = $"($root)/node_modules/.bin/tsc"
  let tsconfig = $"($root)/tsconfig.json"
  if ($tsc_bin | path exists) and ($tsconfig | path exists) {
    run-typecheck $root $"($tsc_bin) --noEmit" $file_abs $root
  }
}
