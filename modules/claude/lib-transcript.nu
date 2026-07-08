# Shared transcript helpers for Claude Code hook scripts (sourced via
# `use ~/.claude/lib-transcript.nu`). Both the desktop-notification hook
# (notify-if-question.nu) and the tmux dot indicator (tmux-claude-indicator.nu)
# need the text of the message Claude just finished, so the extraction lives
# here once.

# Text of the most recent assistant message that has non-empty text content,
# found by walking the transcript backward. Returns "" on any failure (missing
# path, unreadable file, no such message) so callers can fall back to a default.
# Keys on `message.role` — the authoritative author field — rather than the
# top-level `type`, which can also be "attachment", "summary", etc.
export def last-assistant-text [transcript_path: string]: nothing -> string {
  if ($transcript_path | is-empty) { return "" }
  let lines = try {
    open $transcript_path | lines
  } catch { return "" }
  for line in ($lines | reverse) {
    let parsed = try {
      $line | from json
    } catch { continue }
    if ($parsed | get -o message.role | default "") != "assistant" { continue }
    let text = (
      $parsed | get -o message.content | default []
      | where type? == "text" | get -o text | default [] | str join (char nl)
    )
    if ($text | str trim | is-not-empty) { return $text }
  }
  ""
}
