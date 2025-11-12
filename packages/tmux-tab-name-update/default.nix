{
  writeShellApplication,
  tmux,
  git,
}:
writeShellApplication {
  name = "tmux-tab-name-update";
  runtimeInputs = [
    tmux
    git
  ];
  text = ''
    if [[ -n ''${TMUX:-} ]]; then
      pane_id=""
      pane_dir=""

      # If TMUX_TAB_UPDATE_PANE is set, use that pane
      if [[ -n ''${TMUX_TAB_UPDATE_PANE:-} ]]; then
        pane_id="''${TMUX_TAB_UPDATE_PANE}"
        unset TMUX_TAB_UPDATE_PANE
        pane_dir=$(tmux display-message -p -t "$pane_id" '#{pane_current_path}')
      else
        # Otherwise, only update if this pane is currently active
        active_pane=$(tmux display-message -p '#{pane_id}')
        if [[ "''${TMUX_PANE}" == "$active_pane" ]]; then
          pane_id="''${TMUX_PANE}"
          pane_dir="$PWD"
        fi
      fi

      # If we have a pane to update, do it
      if [[ -n "$pane_id" ]]; then
        tab_name=""
        if git -C "$pane_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          tab_name+=$(basename "$(git -C "$pane_dir" rev-parse --show-toplevel)")/
          tab_name+=$(git -C "$pane_dir" rev-parse --show-prefix)
          tab_name=''${tab_name%/}
        else
          tab_name=$pane_dir
          if [[ "$tab_name" == "$HOME" ]]; then
            tab_name="~"
          else
            tab_name=''${tab_name##*/}
          fi
        fi
        command nohup tmux rename-window -t "$pane_id" "$tab_name" >/dev/null 2>&1
      fi
    fi
  '';
}
