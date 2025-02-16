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
      tab_name=""
      if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        tab_name+=$(basename "$(git rev-parse --show-toplevel)")/
        tab_name+=$(git rev-parse --show-prefix)
        tab_name=''${tab_name%/}
      else
        tab_name=$PWD
        if [[ "$tab_name" == "$HOME" ]]; then
          tab_name="~"
        else
          tab_name=''${tab_name##*/}
        fi
      fi
      command nohup tmux rename-window "$tab_name" >/dev/null 2>&1
    fi
  '';
}
