# tmux-tab-name-update 📛

Update tmux tab names based on the directory you are in, intelligently handling background panes.

## Features

- Shows repository name and path for git repositories
- Shows directory name for non-git directories
- **Only updates tabs for active panes or when commands complete in the pane where they started**
- Prevents background command completions from renaming your current tab

## How it works

The tool uses a two-hook approach:

1. `pre_execution` - Marks which pane is about to execute a command
2. `pre_prompt` - Updates the tab name only for:
   - The pane where a command just completed (even if you switched away)
   - The currently active pane (for initial prompt and switching)

This prevents the common issue where:

1. You run a long command in pane A
2. Switch to pane B
3. Command completes in pane A
4. Your current tab (pane B) gets incorrectly renamed ❌

## Usage

```sh
nix run github:xav-ie/dots#tmux-tab-name-update
```

## Installation

Add this to your NixOS flake:

```nix
inputs = {
  xav-ie.url = "github:xav-ie/dots";
};
```

### For Nushell

```nix
programs.nushell = {
  extraConfig = ''
    $env.config.hooks.pre_execution = [
      { || $env.TMUX_TAB_UPDATE_PANE = $env.TMUX_PANE }
    ]

    $env.config.hooks.pre_prompt = [
      { || ${inputs.xav-ie.packages.${pkgs.system}.tmux-tab-name-update}/bin/tmux-tab-name-update }
    ]
  '';
};
```

### For Zsh

```nix
programs.zsh = {
  initExtra = ''
    preexec() {
      export TMUX_TAB_UPDATE_PANE="$TMUX_PANE"
    }

    precmd() {
      ${inputs.xav-ie.packages.${pkgs.system}.tmux-tab-name-update}/bin/tmux-tab-name-update
    }
  '';
};
```

### For Bash

```nix
programs.bash = {
  initExtra = ''
    preexec() {
      export TMUX_TAB_UPDATE_PANE="$TMUX_PANE"
    }

    PROMPT_COMMAND="${inputs.xav-ie.packages.${pkgs.system}.tmux-tab-name-update}/bin/tmux-tab-name-update"
  '';
};
```

Note: Bash requires a preexec hook implementation. Consider using [bash-preexec](https://github.com/rcaloras/bash-preexec).

[..](..)
