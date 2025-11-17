#!/usr/bin/env bash

# Update current tmux tab name.

# Only run if we're in tmux.
[[ -z ${TMUX_PANE} ]] && exit 0

# Prefer invoked-with pane id. Otherwise, use current pane id.
pane_id="${TMUX_TAB_UPDATE_PANE:-$TMUX_PANE}"
pane_dir="$PWD"

# Get git prefix and remove trailing slash and newline
# Use || true to prevent exit on failure in non-git directories
git_prefix=$(git -C "$pane_dir" rev-parse --show-prefix 2>/dev/null || true)
git_prefix="${git_prefix%$'\n'}" # remove newline
git_prefix="${git_prefix%/}"     # remove trailing slash

git_prefix_len="${#git_prefix}"
binary_git_prefix=$((!!git_prefix_len))

# Calculate trimmed_base without conditionals
pane_dir_len=${#pane_dir}
keep_len=$((pane_dir_len - git_prefix_len - binary_git_prefix))
trimmed_base=$(basename "${pane_dir:0:keep_len}")

trimmed_base_len="${#trimmed_base}"
final_index=$((trimmed_base_len + git_prefix_len + binary_git_prefix - 1))

if [[ $pane_dir == "$HOME" ]]; then
  tab_name="~"
else
  # Build tab_name_raw and substring it
  tab_name_raw="${trimmed_base}/${git_prefix}"
  tab_name="${tab_name_raw:0:final_index+1}"
fi

# Use exec to replace process and background for maximum speed
exec sh -c "tmux rename-window -t '$pane_id' '$tab_name' &"
