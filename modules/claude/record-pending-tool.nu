#!/usr/bin/env -S nu --stdin

# Owns the per-session state file that the notification hooks read to describe
# a prompt.
#
# PreToolUse: stash the tool about to run, keyed by session, in the pending-tool
# file. At permission-prompt time the pending tool_use is NOT yet in the
# transcript (the assistant turn is held open while awaiting approval) and the
# Notification payload carries no tool data — only a generic message. PreToolUse
# fires just before the permission check and DOES receive tool_name + tool_input.
#
# SessionEnd: delete the file so /tmp does not accumulate state per session.
def main [] {
  let input = $in | from json
  let sid = $input.session_id? | default "unknown"
  let event = $input.hook_event_name? | default ""
  let toolfile = $"/tmp/claude-pending-tool-($sid).json"

  match $event {
    "SessionEnd" => {
      rm -f $toolfile
    }
    _ => {
      {
        tool_name: ($input.tool_name? | default "")
        tool_input: ($input.tool_input? | default {})
      }
      | to json
      | save -f $toolfile
    }
  }
  exit 0
}
