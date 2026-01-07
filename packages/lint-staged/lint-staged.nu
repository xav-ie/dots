#!/usr/bin/env -S nu --stdin

def --wrapped main [...args] {
  ^npx eslint ...($args | default []) ...(git diff --cached --name-only --diff-filter=d | lines)
}
