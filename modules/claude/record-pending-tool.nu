#!/usr/bin/env -S nu --stdin

use ~/.claude/lib-focus.nu pane-focused

# Owns the per-session state files that the notification hooks read to describe
# a prompt and to decide whether the user already saw it.
#
# PreToolUse: stash the tool about to run, keyed by session, in the pending-tool
# file. At permission-prompt time the pending tool_use is NOT yet in the
# transcript (the assistant turn is held open while awaiting approval) and the
# Notification payload carries no tool data — only a generic message. PreToolUse
# fires just before the permission check and DOES receive tool_name + tool_input.
# For AskUserQuestion we also record whether the user was looking at this pane
# the moment the question was presented; notify.nu suppresses the ping if so.
# (Scoped to AskUserQuestion so the focus query adds no latency to ordinary
# tool calls.)
#
# Stop: a turn finished (a plain text response, possibly ending in a question).
# Record whether the user was looking at this pane at completion, in the
# turn-seen file, so notify-if-question.nu (which fires later, on idle_prompt,
# by which point focus may have changed) can suppress the ping if they saw it.
#
# SessionEnd: delete both files so /tmp does not accumulate state per session.
def main [] {
  let input = $in | from json
  let sid = ($input.session_id? | default "unknown")
  let event = ($input.hook_event_name? | default "")
  let toolfile = $"/tmp/claude-pending-tool-($sid).json"
  let seenfile = $"/tmp/claude-turn-seen-($sid).json"

  match $event {
    "SessionEnd" => {
      rm -f $toolfile $seenfile
    }
    "Stop" => {
      { seen: (pane-focused) } | to json | save -f $seenfile
    }
    _ => {
      let tool = ($input.tool_name? | default "")
      let seen = (if ($tool == "AskUserQuestion") { (pane-focused) } else { false })
      {
        tool_name: $tool
        tool_input: ($input.tool_input? | default {})
        seen: $seen
      }
      | to json
      | save -f $toolfile
    }
  }
  exit 0
}
