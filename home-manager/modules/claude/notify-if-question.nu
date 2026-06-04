#!/usr/bin/env -S nu --stdin

use ~/.claude/lib-transcript.nu last-assistant-text

# Notification hook for the `idle_prompt` event (Claude finished and is waiting).
# Claude Code's built-in idle notification ("Claude is waiting for your input")
# is silenced via `preferredNotifChannel: notifications_disabled`; this replaces
# it with a quieter rule: only notify when the output just given actually asks
# something, i.e. the last assistant message contains a "?". Real permission /
# AskUserQuestion prompts arrive on the separate `permission_prompt` hook.
def main [] {
  let input = $in | from json
  let last_text = (last-assistant-text ($input.transcript_path? | default ""))

  if ($last_text | str contains "?") {
    let preview = ($last_text | str trim | str substring 0..200)
    ^notify "Claude Code" $preview
  }

  exit 0
}
