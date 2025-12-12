#!/usr/bin/env -S nu --stdin

def main [] {
  let input = $in | from json
  # save last assistant response to file
  try {

    let last_message = (open $input.transcript_path
                        | lines
                        | last
                        | from json)
    let content = ($last_message.message.content | first)
    $content | to json | save -f /tmp/transcript.txt

    match $content.type {
      "tool_use" => {
        match $content.name {
          "AskUserQuestion" => {
            ^notify "Claude Code" "Needs answers to some question(s)"
          }
          "Edit" => {
            let basepath = ($content.input.file_path | path basename)
            ^notify "Claude Code" $"Needs permission to edit ($basepath)"
          }
          "EnterPlanMode" => {
            ^notify "Claude Code" $"Needs permission to enter plan mode"
          }
          "Bash" => {
            ^notify "Claude Code" $"Bash: ($content.input.description)"
          }
          "Glob" => {
            let basepath = ($content.input.path? | default "cwd" | path basename)
            ^notify "Claude Code" $"Needs permission to glob search ($basepath)"
          }
          "Grep" => {
            let basepath = ($content.input.path? | default "cwd" | path basename)
            ^notify "Claude Code" $"Needs permission to search ($basepath)"
          }
          "Read" => {
            let basepath = ($content.input.file_path | path basename)
            ^notify "Claude Code" $"Needs permission to read ($basepath)"
          }
          "SlashCommand" => {
            ^notify "Claude Code" $"Needs permission to run ($content.input.command)"
          }
          "Task" => {
            ^notify "Claude Code" $"Subagent ($content.input.subagent_type): ($content.input.description)"
          }
          "WebFetch" => {
            ^notify "Claude Code" $"Needs permission to fetch ($content.input.url)"
          }
          "Write" => {
            let basepath = ($content.input.file_path | path basename)
            ^notify "Claude Code" $"Needs permission to create ($basepath)"
          }
          _ => {
            if ($content.name | str starts-with "mcp__") {
              let mcp = $content.name | parse "mcp__{server}__{tool}" | first
              ^notify "Claude Code" $"($mcp.server) permission to run ($mcp.tool)"
              exit 0
            }
            ^notify "Unknown tool name" $content.name
            exit 1
          }
        }
      }
      _ => {
        ^notify "Unknown message type" $content.type
        exit 1
      }
    }

    exit 0
  }

  ^notify "Claude Code" $input.message
}
