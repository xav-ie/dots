let LIGHT_THEME = "'prefer-light'"
let DARK_THEME = "'prefer-dark'"
let THEME_PATH = "/org/gnome/desktop/interface/color-scheme"
let SIGWINCH = 28 # Window size change signal

# Recursively get all descendant PIDs
def get_descendants [parent_pid: int] {
  let children = try {
    (
      ^pgrep -P $parent_pid
      | lines
      | where $it != ""
      | par-each {|p| ($p | str trim | into int) }
    )
  } catch {
    []
  }

  let all_descendants = $children | par-each { |child|
    [$child] | append (get_descendants $child)
  } | flatten

  ($children | append $all_descendants | uniq)
}

# Get relevant PIDs which would like SIGWINCH: the herdr servers/clients and
# everything running inside their panes.
def get_pids [] {
  let herdr_pids = (
    try {
      ^pgrep herdr | lines | where $it != "" | each {|pid| ($pid | str trim | into int) }
    } catch { [] }
  )

  (
    $herdr_pids
    | append ($herdr_pids | par-each {|p| get_descendants $p } | flatten)
    | uniq
  )
}

def get_theme [] {
  (dconf read $THEME_PATH | str trim)
}

def set_theme [theme, pids] {
  dconf write $THEME_PATH $theme
  try { kill --signal $SIGWINCH ...$pids }
  # Schedule another SIGWINCH after 30 seconds to handle rate-limited case
  let pids_args = $pids | each {|p| $p | into string }
  ^sh -c '(sleep 31 && kill -28 "$@" 2>/dev/null) &' _ ...$pids_args
}

def get_toggle [] {
  let current_theme = (get_theme)
  if $current_theme == $LIGHT_THEME {
    $DARK_THEME
  } else if $current_theme == $DARK_THEME {
    $LIGHT_THEME
  } else {
    error make -u {msg: $"❌ Failed to match theme: ($current_theme)"}
  }
}

def main [] {
  set_theme (get_toggle) (get_pids)
  print "✓ Theme toggled"
}
