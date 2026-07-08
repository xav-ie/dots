#!/usr/bin/env -S nu --stdin

def --wrapped main [...args] {
  let flags = ($args | where {|a| ($a | str starts-with '-')})
  let explicit_files = ($args | where {|a| not ($a | str starts-with '-')})
  let files = if ($explicit_files | is-empty) {
    git diff --cached --name-only --diff-filter=d | lines
  } else {
    $explicit_files
  }
  if ($files | is-empty) { return }
  ^npx prettier --cache --write ...$flags ...$files
}
