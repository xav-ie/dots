#!/usr/bin/env nu

# Update current tmux tab name.
def main [] {
  # Only run if we're in tmux.
  if ('TMUX_PANE' not-in $env) {
    return
  }

  # Prefer invoked-with pane id. Otherwise, use current pane id.
  let pane_id = $env.TMUX_TAB_UPDATE_PANE? | default $env.TMUX_PANE

  let pane_dir = $env.PWD

  # remove trailing slash and newline
  let git_prefix = (^git -C $pane_dir rev-parse --show-prefix
                    | complete
                    | get stdout
                    | str substring 0..-3)

  let git_prefix_len = $git_prefix | str length
  let binary_git_prefix = $git_prefix_len != 0 | into int

  let end_index = ($git_prefix_len * -1) - 1
  let trimmed_base = $pane_dir | str substring 0..$end_index | path basename
  let trimmed_base_len = $trimmed_base | str length

  let final_index = $trimmed_base_len + $git_prefix_len + $binary_git_prefix - 1
  let tab_name = if $pane_dir == $env.HOME {
    "~"
  } else {
    ($trimmed_base + "/" + $git_prefix) | str substring 0..$final_index
  }

  # Use sh to spawn completely detached process for maximum speed
  exec sh -c $"tmux rename-window -t '($pane_id)' '($tab_name)' &"
}
