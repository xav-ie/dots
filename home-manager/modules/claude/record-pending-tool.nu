#!/usr/bin/env -S nu --stdin

# Owns the per-session "pending tool" state file that the permission_prompt
# Notification hook (notify.nu) reads.
#
# On PreToolUse: stash the tool about to run. At permission-prompt time the
# pending tool_use is NOT yet in the transcript (the assistant turn is held open
# while awaiting approval) and the Notification payload carries no tool data —
# only a generic message. PreToolUse fires just before the permission check and
# DOES receive tool_name + tool_input, so we record them here, keyed by session.
#
# On SessionEnd: delete the file so /tmp does not accumulate one stash per
# session forever.
def main [] {
  let input = $in | from json
  let sid = ($input.session_id? | default "unknown")
  let statefile = $"/tmp/claude-pending-tool-($sid).json"

  if (($input.hook_event_name? | default "") == "SessionEnd") {
    rm -f $statefile
    exit 0
  }

  {
    tool_name: ($input.tool_name? | default "")
    tool_input: ($input.tool_input? | default {})
  }
  | to json
  | save -f $statefile
  exit 0
}
