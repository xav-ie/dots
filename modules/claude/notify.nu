#!/usr/bin/env -S nu --stdin

# Claude's notifications: Claude avatar, gone after a day, and a click focuses
# the herdr tab this session runs in.
def claude-notify [title: string, body: string] {
  let tab = $env.HERDR_TAB_ID? | default ""
  let tab_flag = if ($tab | is-empty) { [] } else { [--herdr-tab $tab] }
  ^notify $title $body --icon claude --expire 1day ...$tab_flag
}

def main [] {
  let input = $in | from json
  # The Notification:permission_prompt payload carries no tool data, and the
  # pending tool_use is not yet in the transcript (the assistant turn is held
  # open while awaiting approval). The PreToolUse hook (record-pending-tool.nu)
  # stashes the tool that is about to run, keyed by session, so read it back.
  let sid = $input.session_id? | default "unknown"
  let statefile = $"/tmp/claude-pending-tool-($sid).json"
  let pending = (try { open $statefile } catch { null })

  # No recorded tool: fall back to the raw hook message, the same generic ping
  # Claude Code would otherwise show.
  if $pending == null {
    claude-notify "Claude Code" $input.message
    exit 0
  }

  # Dedup: permission_prompt can fire repeatedly for the same unanswered prompt
  # (Claude re-pings while you stay idle / leave the pane). Notify once per
  # recorded tool. A genuinely new tool call rewrites this file via PreToolUse
  # without the flag, which re-enables notifying.
  if ($pending.notified? | default false) { exit 0 }
  $pending | upsert notified true | to json | save -f $statefile

  let content = {
    name: ($pending.tool_name? | default "")
    input: ($pending.tool_input? | default {})
  }

  match $content.name {
    "AskUserQuestion" => {

      # input.questions is [{question, header, options, multiSelect}, ...];
      # surface the actual prompt text instead of a generic placeholder.
      let questions = $content.input.questions? | default []
      let body = if ($questions | is-empty) {
        "Needs answers to some question(s)"
      } else {
        $questions | get question | str join (char nl)
      }
      claude-notify "Claude has a question" $body
    }
    "Edit" => {
      let basepath = $content.input.file_path | path basename
      claude-notify "Claude Code" $"Needs permission to edit ($basepath)"
    }
    "EnterPlanMode" => {
      claude-notify "Claude Code" $"Needs permission to enter plan mode"
    }
    "Bash" => {
      claude-notify "Claude Code" $"Bash: ($content.input.description)"
    }
    "Glob" => {
      let basepath = $content.input.path? | default "cwd" | path basename
      claude-notify "Claude Code" $"Needs permission to glob search ($basepath)"
    }
    "Grep" => {
      let basepath = $content.input.path? | default "cwd" | path basename
      claude-notify "Claude Code" $"Needs permission to search ($basepath)"
    }
    "Read" => {
      let basepath = $content.input.file_path | path basename
      claude-notify "Claude Code" $"Needs permission to read ($basepath)"
    }
    "SlashCommand" => {
      claude-notify "Claude Code" $"Needs permission to run ($content.input.command)"
    }
    "Task" => {
      claude-notify "Claude Code" $"Subagent ($content.input.subagent_type): ($content.input.description)"
    }
    "WebFetch" => {
      claude-notify "Claude Code" $"Needs permission to fetch ($content.input.url)"
    }
    "Write" => {
      let basepath = $content.input.file_path | path basename
      claude-notify "Claude Code" $"Needs permission to create ($basepath)"
    }
    _ => {
      if ($content.name | str starts-with "mcp__") {
        let mcp = $content.name | parse "mcp__{server}__{tool}" | first
        claude-notify "Claude Code" $"($mcp.server) permission to run ($mcp.tool)"
        exit 0
      }
      claude-notify "Unknown tool name" $content.name
      exit 1
    }
  }
}
