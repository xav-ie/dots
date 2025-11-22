let LIGHT_THEME = "'prefer-light'"
let DARK_THEME = "'prefer-dark'"
let THEME_PATH = "/org/gnome/desktop/interface/color-scheme"
let SIGWINCH = 28 # Window size change signal

# Recursively get all descendant PIDs
def get_descendants [parent_pid: int] {
  let children = try {
    (^pgrep -P $parent_pid | lines | where $it != "" | par-each { |p| ($p | str trim | into int) })
  } catch {
    []
  }

  let all_descendants = $children | par-each { |child|
    [$child] | append (get_descendants $child)
  } | flatten

  ($children | append $all_descendants | uniq)
}

# Get relevant PIDs which would like SIGWINCH
def get_pids [] {
  # Get all tmux server/client PIDs (without -x flag to match "tmux attach" etc)
  let tmux_pids = (^pgrep tmux | lines | where $it != "" | each { |pid| ($pid | str trim | into int) })

  # Get all pane processes
  let pane_pids = (^tmux list-panes -a -F "#{pane_pid}:#{pane_tty}" | lines | where $it != "")
    | par-each -k { |entry|
      let parts = ($entry | split column ":" pane_pid pane_tty | get 0)
      let pane_pid = $parts.pane_pid | into int
      let tty = $parts.pane_tty

      # Get processes on the TTY
      let tty_pids = if $tty != "" and $tty != "-" {
        (^ps -o pid= -t $tty | lines | where $it != "" | each { |pid| ($pid | str trim | into int) })
      } else {
        []
      }

      # Get all recursive descendants of the pane PID
      let descendant_pids = (get_descendants $pane_pid)

      ($tty_pids | append $descendant_pids)
    }
    | flatten

  # Combine tmux PIDs with pane PIDs
  ($tmux_pids | append $pane_pids | uniq)
}

def get_theme [] {
  (dconf read $THEME_PATH | str trim)
}

def set_theme [theme, pids] {
  dconf write $THEME_PATH $theme
  try { kill --signal $SIGWINCH ...$pids }
  # Schedule another SIGWINCH after 30 seconds to handle rate-limited case
  let pids_str = ($pids | each { |p| $"($p)" } | str join " ")
  sh -c $"\(sleep 31 && kill -28 ($pids_str) 2>/dev/null\) &"
}

def get_toggle [] {
  let current_theme = (get_theme)
  if $current_theme == $LIGHT_THEME {
    $DARK_THEME
  } else if $current_theme == $DARK_THEME {
    $LIGHT_THEME
  } else {
    error make -u { msg: $"❌ Failed to match theme: ($current_theme)" }
  }
}

def main [] {
  set_theme (get_toggle) (get_pids)
  print "✓ Theme toggled"
}
