#!/usr/bin/env -S nu --stdin

def main [
  --commits (-c): string  # Commit range or ref (e.g. HEAD~3..HEAD, HEAD~3)
  ...files: string        # Specific files to format and lint
] {
  if ($commits != null) {
    let changed = (git diff --name-only --diff-filter=d $commits | lines)
    if ($changed | is-empty) {
      print "No files changed in the given commit range."
      return
    }
    format-staged ...$changed
    lint-staged --fix ...$changed
  } else if not ($files | is-empty) {
    format-staged ...$files
    lint-staged --fix ...$files
  } else {
    format-staged
    lint-staged --fix
  }
}
