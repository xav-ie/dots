#!/usr/bin/env bash
# The claude wrapper runs with --setting-sources user, so the engine loads no
# project CLAUDE.md or AGENTS.md. This names them instead, once per directory
# per agent: the cwd and its ancestors at session or subagent start, and each
# directory a Read, Edit or Write first reaches below that. The agent decides
# what to read. The walk stops at $HOME, $HOME/.claude and /, so the user
# memory ($HOME/.claude/CLAUDE.md, already loaded) is never listed.
set -euo pipefail

input=$(cat)
field() { jq -r ".$1 // empty" <<<"$input"; }

event=$(field hook_event_name)
session=$(field session_id)
agent=$(field agent_id)
cwd=$(field cwd)

dir="${XDG_RUNTIME_DIR:-/tmp}/claude-project-instructions"
seen="$dir/$session${agent:+.$agent}"
mkdir -p "$dir"

case $event in
SessionEnd)
  rm -f "$dir/$session" "$dir/$session".*
  exit 0
  ;;
SessionStart | SubagentStart)
  : >"$seen"
  start=$cwd
  ;;
PostToolUse)
  path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
  [ -n "$path" ] || exit 0
  [[ $path == /* ]] || path="$cwd/$path"
  start=$(dirname "$path")
  ;;
*) exit 0 ;;
esac

found=()
d=$start
while [ "$d" != / ] && [ "$d" != "$HOME" ] && [ "$d" != "$HOME/.claude" ] && ! grep -qxF -- "$d" "$seen" 2>/dev/null; do
  echo "$d" >>"$seen"
  for f in .claude/AGENTS.md .claude/CLAUDE.md AGENTS.md CLAUDE.local.md CLAUDE.md; do
    [ -f "$d/$f" ] && found=("$d/$f" "${found[@]}")
  done
  d=$(dirname "$d")
done

[ ${#found[@]} -gt 0 ] || exit 0

msg="Project instruction files cover this directory. They are not loaded; read the ones that apply before working here:"
for f in "${found[@]}"; do
  msg+=$'\n'"- $f ($(wc -l <"$f") lines)"
done

jq -n --arg e "$event" --arg c "$msg" '{hookSpecificOutput: {hookEventName: $e, additionalContext: $c}}'
