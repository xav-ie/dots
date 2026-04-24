#!/usr/bin/env -S nu --stdin

# Run tsc --noEmit against the given tsconfig and print only diagnostics that
# reference the requested files. The tsconfig defines scope (so ambient types,
# project references, and cross-file inference all work correctly); this tool
# just filters tsc's output to the files you care about.
#
# Exit codes:
#   0 — no diagnostics for the requested files
#   1 — one or more diagnostics reference the requested files
#   2 — usage error (missing config, etc.)

def main [
  --config (-c): string  # path to tsconfig.json (scope for the typecheck)
  ...files: string       # files to report diagnostics for
] {
  if ($config | is-empty) {
    print -e "usage: tsc-filter --config <tsconfig.json> <file>..."
    exit 2
  }
  if not ($config | path exists) {
    print -e $"tsc-filter: tsconfig not found: ($config)"
    exit 2
  }
  if ($files | is-empty) { return }

  let config_abs = ($config | path expand)
  let config_dir = ($config_abs | path dirname)

  # Prefer the git root as the cwd so tsc emits repo-root-relative paths
  # (uniform across monorepos). Falls back to the tsconfig dir if the project
  # isn't in a git repo.
  let run_cwd = (try {
    let res = (^git -C $config_dir rev-parse --show-toplevel | complete)
    if $res.exit_code == 0 { $res.stdout | str trim } else { $config_dir }
  } catch { $config_dir })

  let rel_files = ($files | each {|f|
    let abs = ($f | path expand)
    try { $abs | path relative-to $run_cwd } catch { $abs }
  })

  let local_tsc = ([$config_dir "node_modules" ".bin" "tsc"] | path join)
  let root_tsc = ([$run_cwd "node_modules" ".bin" "tsc"] | path join)
  let tsc_bin = if ($local_tsc | path exists) {
    $local_tsc
  } else if ($root_tsc | path exists) {
    $root_tsc
  } else {
    "tsc"
  }

  cd $run_cwd
  let result = (^$tsc_bin --noEmit -p $config_abs --pretty false | complete)
  let output = (
    [$result.stdout $result.stderr]
    | where {|s| ($s | str trim) != "" }
    | str join "\n"
  )

  # A diagnostic block starts on a non-indented line (the header) and may be
  # followed by indented continuation lines. Keep a block iff its header starts
  # with one of the requested files.
  mut kept = []
  mut keep = false
  for line in ($output | lines) {
    let is_header = not (
      ($line | str starts-with " ")
      or ($line | str starts-with (char tab))
      or ($line | str length) == 0
    )
    if $is_header {
      $keep = ($rel_files | any {|f| $line | str starts-with $f })
    }
    if $keep { $kept = ($kept | append $line) }
  }

  if ($kept | is-empty) { return }
  print ($kept | str join "\n")
  exit 1
}
