#!/usr/bin/env -S nu --stdin

# Toggle the per-window `@claude-dot` tmux option to signal that a Claude
# session has an update awaiting attention. The tmux window-status format
# reads this option to render a colored dot prefix in the status line.
#
# Invoked from Claude hooks (Stop/Notification) to set the color, and from
# tmux `after-select-pane`/`after-select-window` hooks with `clear` to swap to
# a neutral color.
#
# Logging is off by default. Set $TMUX_CLAUDE_INDICATOR_DEBUG=1 to enable
# it; activity is then written to $TMUX_CLAUDE_INDICATOR_LOG (default:
# `~/.cache/tmux-claude-indicator.log`).

use ~/.claude/lib-transcript.nu last-assistant-text

const LOG_DEFAULT = "~/.cache/tmux-claude-indicator.log"

def log [path: string, msg: string] {
  if ($env.TMUX_CLAUDE_INDICATOR_DEBUG? | default "" | is-empty) { return }
  try {
    let line = $"(date now | format date '%Y-%m-%dT%H:%M:%S%.3f') ($msg)\n"
    let p = ($path | path expand)
    mkdir ($p | path dirname)
    $line | save --append $p
  }
}

# Concatenated text of the final assistant message from the Stop hook
# payload (read from stdin). Returns "" on any failure so the caller can
# fall back to its default behavior. Logs each step so failures can be
# inspected in the indicator log.
def stop_final_text [stdin_raw: string, log_path: string] {
  log $log_path $"stop_final_text: stdin len=($stdin_raw | str length)"

  let payload = try { $stdin_raw | from json } catch { |e|
    log $log_path $"stop_final_text: stdin not JSON: ($e.msg)"
    return ""
  }

  let transcript_path = ($payload | get -o transcript_path | default "")
  log $log_path $"stop_final_text: transcript_path=($transcript_path)"

  let text = (last-assistant-text $transcript_path)
  log $log_path $"stop_final_text: text len=($text | str length), preview=($text | str substring 0..120)"
  $text
}

# Returns true if the user can already see this pane right now: its window is
# the current window of an attached session, and the window is either not
# zoomed or zoomed onto this same pane.
def pane_is_visible [pane: string] {
  let raw = try {
    (^tmux display-message -t $pane -p "#{window_active}|#{window_zoomed_flag}|#{pane_active}|#{session_attached}") | str trim
  } catch { return false }

  let parts = ($raw | split row "|")
  if ($parts | length) < 4 { return false }

  let window_active = (($parts | get 0) == "1")
  let window_zoomed = (($parts | get 1) == "1")
  let pane_active = (($parts | get 2) == "1")
  let attached = ((($parts | get 3) | into int) > 0)

  $window_active and $attached and ((not $window_zoomed) or $pane_active)
}

def main [event: string, pane_override?: string] {
  let stdin_raw = ($in | default "")
  let log_path = $env.TMUX_CLAUDE_INDICATOR_LOG? | default $LOG_DEFAULT

  let pane = if $pane_override == null or ($pane_override | is-empty) {
    $env.TMUX_PANE? | default ""
  } else {
    $pane_override
  }

  let in_tmux = not ($env.TMUX? | default "" | is-empty)
  let override_str = ($pane_override | default "<none>")
  log $log_path $"invoke event=($event) pane=($pane) override=($override_str) in_tmux=($in_tmux)"

  if ($pane | is-empty) {
    log $log_path "skip: no pane id, not inside tmux?"
    return
  }

  # Skip alerts when Claude's pane is already visible to the user — i.e. some
  # client has this window current AND the window is either not zoomed or
  # zoomed onto Claude's own pane. Clears always proceed.
  if $event != "clear" and (pane_is_visible $pane) {
    log $log_path $"skip: pane ($pane) is already visible to the user"
    return
  }

  # "clear" is a sentinel — the tmux format swaps it for grey (inactive
  # window) or white (active window) so the dot still indicates focus.
  # Stop is normally green; if the final assistant message contains "?"
  # we upgrade it to yellow so a pending question stands out.
  let color = match $event {
    "stop" => {
      let text = stop_final_text $stdin_raw $log_path
      if ($text | str contains "?") {
        log $log_path "stop -> yellow: '?' detected in final message"
        "yellow"
      } else { "green" }
    }
    "notification" => "yellow"
    "clear" => "clear"
    _ => "white"
  }

  try {
    ^tmux set-option -w -t $pane "@claude-dot" $color
    log $log_path $"set pane=($pane) color=($color)"
  } catch { |e|
    log $log_path $"error set-option failed: ($e.msg)"
  }
}
