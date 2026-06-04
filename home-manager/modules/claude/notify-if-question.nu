#!/usr/bin/env -S nu --stdin

use ~/.claude/lib-transcript.nu last-assistant-text

# Notification hook for the `idle_prompt` event (Claude finished and is waiting).
# Claude Code's built-in idle notification ("Claude is waiting for your input")
# is silenced via `preferredNotifChannel: notifications_disabled`; this replaces
# it with a quieter rule: only notify when Claude is actually asking a question
# back. We judge that on the *last paragraph* of the message — a "?" earlier in
# the reply (rhetorical, code, a clarifying aside) does not count, and the
# notification body shows that closing paragraph rather than the opening lines.
# Real permission / AskUserQuestion prompts arrive on the separate
# `permission_prompt` hook.

# Trailing block of the message: split on blank lines, drop empty/whitespace
# blocks, take the last. Markdown paragraphs (and list-item groups) are
# separated by blank lines, so this isolates the closing thought.
def last-paragraph [text: string]: nothing -> string {
  let paras = (
    $text
    | str trim
    | split row -r '\n[ \t]*\n'
    | each { str trim }
    | where { is-not-empty }
  )
  $paras | last 1 | get -o 0 | default ""
}

def main [] {
  let input = $in | from json
  let last_text = (last-assistant-text ($input.transcript_path? | default ""))
  let para = (last-paragraph $last_text)

  if ($para | str contains "?") {
    let preview = ($para | str substring 0..200)
    ^notify "Claude has a question" $preview
  }

  exit 0
}
