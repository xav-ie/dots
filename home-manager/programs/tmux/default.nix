{ pkgs, lib, ... }:
{
  config = {
    programs.tmux = {
      enable = true;
      baseIndex = 1;
      keyMode = "vi";
      # focusEvents = true; #?
      mouse = true;
      newSession = true;
      plugins = with pkgs.tmuxPlugins; [
        # allows seamless window/pane navigation with nvim
        # needs the accompanying vim plugin
        # https://github.com/christoomey/vim-tmux-navigator/
        vim-tmux-navigator
        # adds helpful selection commands
        # https://github.com/tmux-plugins/tmux-copycat
        copycat
      ];
      shell = lib.getExe pkgs.pkgs-bleeding.nushell;
      shortcut = "Space";
      terminal = "xterm-256color";
      extraConfig = # tmux
        ''
          bind -n M-H previous-window
          bind -n M-L next-window
          # open next panes in same directory
          bind '"' split-window -c "#{pane_current_path}"
          bind 'j' split-window -c "#{pane_current_path}"
          bind '%' split-window -h -c "#{pane_current_path}"
          bind ';' split-window -h -c "#{pane_current_path}"
          unbind-key -n C-.
          bind-key -n C-. send-keys C-. 
          set -s set-clipboard on
          unbind r
          bind r command-prompt -I "#W" "rename-window '%%'"

          set-option -g status-style bg=default,fg=colour255
          set-option -g status-left " "
          set-option -g status-right "#{?client_prefix, PREFIX ,}#{?pane_in_mode, COPY ,} #[fg=colour255,bg=colour238] #S #[default]"
          set-option -g status-right "#{mode_indicator} #[fg=colour255,bg=colour238] #S #[default]"
          set-option -g window-status-format "#[fg=colour244]#W#[default]"
          set-option -g window-status-current-format "#[fg=colour255,bold]#W#[default]"
        '';
    };
  };
}
