#!/usr/bin/env -S nu --stdin

def --wrapped main [...args] {
  let files = git diff --cached --name-only --diff-filter=d | lines | where {|f| not ($f =~ '\.(scss|css)$')}
  ^npx eslint ...($args | default []) ...$files
}
