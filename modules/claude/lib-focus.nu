# Focus detection for Claude Code hook scripts (sourced via
# `use ~/.claude/lib-focus.nu pane-focused`).
#
# A hook runs as a child of Claude Code, so it inherits TMUX / TMUX_PANE and can
# ask: is the tmux pane I am running in the one the user is actually looking at
# right now? The notification hooks use this to skip pinging the user about a
# prompt they have already seen.

# True when this hook's tmux pane is BOTH visible inside tmux (the active pane of
# the current window in an attached session, not zoomed onto another pane) AND
# the terminal hosting it is Hyprland's focused window. The tmux check alone is
# not enough: a backgrounded terminal still reports its active pane as "visible",
# so the OS-focus check is what distinguishes "looking at it" from "tabbed away".
#
# Returns false whenever focus cannot be confirmed (not in tmux, tmux/hyprctl
# unavailable, etc.) — better to notify than to silently swallow an unseen prompt.
export def pane-focused []: nothing -> bool {
  let pane = $env.TMUX_PANE? | default ""
  if ($pane | is-empty) { return false }

  # Within tmux: window current, session attached, not zoomed onto a different
  # pane. Mirrors pane_is_visible in tmux-claude-indicator.nu.
  let raw = (
    try {
      ^tmux display-message -p -t $pane '#{session_name}|#{window_active}|#{window_zoomed_flag}|#{pane_active}|#{session_attached}'
      | str trim
    } catch { "" }
  )
  let parts = $raw | split row "|"
  if ($parts | length) < 5 { return false }
  let sess = $parts | get 0
  let window_active = ($parts | get 1) == "1"
  let zoomed = ($parts | get 2) == "1"
  let pane_active = ($parts | get 3) == "1"
  let attached = (($parts | get 4) | into int) > 0
  if not ($window_active and $attached and ((not $zoomed) or $pane_active)) { return false }

  # OS focus: Hyprland's active window must be an ancestor of one of the tmux
  # clients attached to this session (i.e. the terminal showing it is focused).
  let active = (
    try {
      ^hyprctl activewindow -j | from json | get -o pid
    } catch { null }
  )
  if $active == null { return false }
  let clients = (
    try { ^tmux list-clients -t $sess -F '#{client_pid}' | lines | where { is-not-empty } } catch { [] }
  )
  for cpid in $clients {
    mut p = $cpid | into int
    for _ in 1..20 {
      if $p == $active { return true }
      let ppid = (
        try {
          ^ps -o ppid= -p $p | str trim | into int
        } catch { 0 }
      )
      if $ppid <= 1 { break }
      $p = $ppid
    }
  }
  false
}
