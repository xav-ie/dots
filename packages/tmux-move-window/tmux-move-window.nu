# Move current tmux window to target position by repeatedly swapping
def main [target: int] {
  # Get current window index
  let current: int = (tmux display-message -p "#{window_index}" | into int)

  if $current == $target {
    print $"Already at position ($target)"
    return
  }

  # Repeatedly swap towards target position
  if $target < $current {
    # Moving left: swap repeatedly with previous window
    ($current..($target + 1)) | each { |pos|
      ^tmux swap-window -s $pos -t ($pos - 1)
    } | ignore
  } else {
    # Moving right: swap repeatedly with next window
    ($current..($target - 1)) | each { |pos|
      ^tmux swap-window -s $pos -t ($pos + 1)
    } | ignore
  }

  # Select the window at target position (which is now our window)
  ^tmux select-window -t $target
}
