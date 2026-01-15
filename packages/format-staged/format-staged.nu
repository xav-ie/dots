#!/usr/bin/env -S nu --stdin

def --wrapped main [...args] {
  let files = git diff --cached --name-only --diff-filter=d | lines
  ^npx prettier --cache --write ...($args | default []) ...$files
}
