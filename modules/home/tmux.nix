{
  flake.modules.homeManager.common =
    { pkgs, ... }:
    let
      # vim-tmux-navigator's default is_vim check is `ps -t <pane_tty>` +
      # regex on `comm`. atuin hex (see ../atuin) owns each pane's tty and
      # runs nu (and therefore nvim) on an inner pty — so the default check
      # only ever sees `atuin` and tmux falls through to select-pane, making
      # Ctrl+H/J/K/L skip vim splits entirely.  This Rust helper walks
      # descendants past atuin to find nvim; it reads the whole process table
      # in one pass (the bash port spawned ps/pgrep per BFS level and was too
      # slow to run on every keypress).
      isVimInTree = "${pkgs.pkgs-mine.tmux-is-vim-in-tree}/bin/tmux-is-vim-in-tree";
    in
    {
      config = {
        programs.tmux = {
          enable = true;
          baseIndex = 1;
          keyMode = "vi";
          focusEvents = true;
          mouse = true;
          newSession = true;
          plugins = with pkgs.tmuxPlugins; [
            # NOTE: tmux-continuum is intentionally NOT listed here. It injects its
            # auto-save trigger by prepending an interpolation onto status-right at
            # load time, and home-manager always sources `plugins` before
            # `extraConfig`. Listed here it would load before our status-right is
            # set, then extraConfig's `set status-right` would overwrite (and
            # discard) the save trigger -> nothing ever saves. Instead we run it by
            # hand at the very end of extraConfig, after status-right exists.
            # adds helpful selection commands
            # https://github.com/tmux-plugins/tmux-copycat
            copycat
            # save/restore sessions, windows, panes, layouts, working dirs
            # https://github.com/tmux-plugins/tmux-resurrect
            resurrect
            # nushell-patched fork of timvw/tmux-assistant-resurrect; hooks into
            # resurrect's post-save/post-restore to track Claude Code session IDs
            # and replay `claude --resume <id>` per pane.  Must load after resurrect.
            pkgs.pkgs-mine.tmux-claude-resurrect
            # allows seamless window/pane navigation with nvim
            # needs the accompanying vim plugin
            # https://github.com/christoomey/vim-tmux-navigator/
            {
              plugin = vim-tmux-navigator;
              # Per-plugin extraConfig is emitted BEFORE run-shell, so the
              # plugin's main() reads this when binding C-h/j/k/l. Required
              # because atuin hex (see ../atuin) owns each pane's tty — the
              # default `ps -t` check only ever sees `atuin` and tmux falls
              # through to select-pane, skipping vim splits entirely.
              extraConfig = ''
                set -g @vim_navigator_check "${isVimInTree} '#{pane_tty}'"
              '';
            }
          ];
          # tmux-shell C shim execs `atuin hex --shell nu`.  Direct exec
          # (~0.3 ms) instead of a bash wrapper (~2 ms).
          shell = "${pkgs.pkgs-mine.tmux-shell}/bin/tmux-shell";
          shortcut = "Space";
          # inherit from previous shell
          terminal = "$TERM";
          extraConfig = # tmux
            ''
              # Allow OSC escape sequences to pass through to terminal
              # This enables programs like delta and neovim to detect theme changes
              # "all" allows passthrough from inactive panes too, so image.nvim
              # can clear Kitty graphics on FocusLost after tmux switches away.
              set-option -g allow-passthrough all

              bind -n M-H previous-window
              bind -n M-L next-window
              # insert window at specific index (shifts other windows)
              bind . command-prompt -p "move window to:" "run-shell '${pkgs.pkgs-mine.tmux-move-window}/bin/tmux-move-window %%'"
              # open next panes in same directory
              bind '"' split-window -c "#{pane_current_path}"
              bind 'j' split-window -c "#{pane_current_path}"
              bind '%' split-window -h -c "#{pane_current_path}"
              bind 'l' split-window -h -c "#{pane_current_path}"
              bind -r H resize-pane -L 5
              bind -r J resize-pane -D 5
              bind -r K resize-pane -U 5
              bind -r L resize-pane -R 5

              set-option -g escape-time 5 # ms
              set-option -g history-limit 50000
              set-option -g renumber-windows on
              set-option -g extended-keys on
              set-option -g extended-keys-format csi-u

              set -s set-clipboard on
              unbind r
              bind r command-prompt -I "#W" "rename-window '%%'"

              # Pane borders
              set-option -g pane-border-style fg=colour8
              set-option -g pane-active-border-style fg=colour93
              set-option -g pane-border-indicators both
              set-option -g pane-border-lines heavy

              set-option -g status-style bg=default,fg=default
              set-option -g status-left " "
              # #{continuum_status} just renders continuum's state (running/off); it
              # does not drive saving. The actual periodic-save trigger is a separate
              # interpolation continuum prepends onto status-right when it loads, so
              # continuum must run after this set-option (see end of extraConfig).
              set-option -g status-right "#{?client_prefix, PREFIX ,}#{?pane_in_mode, COPY ,}#{continuum_status}"
              # Conditionally prepend a colored Claude "needs attention" dot. The
              # color lives in the per-window @claude-dot user option (set by
              # ~/.claude/tmux-claude-indicator.nu) rather than embedded in the
              # window name itself, so #W stays plain. The sentinel value `clear`
              # means "no active alert" — rendered grey on inactive windows and
              # white on the active one so focus is still visible.
              set-option -g window-status-format "#{?@claude-dot,#[fg=#{?#{==:#{@claude-dot},clear},colour244,#{@claude-dot}}]● ,}#[fg=colour244]#W#[default]"
              set-option -g window-status-current-format "#{?@claude-dot,#[fg=#{?#{==:#{@claude-dot},clear},white,#{@claude-dot}}]● #[fg=default],}#[bold]#W#[default]"

              # Clear the Claude "needs attention" dot prefix when its pane gets focus.
              set-hook -g pane-focus-in 'run-shell -b "~/.claude/tmux-claude-indicator.nu clear #{pane_id}"'

              unbind-key -n C-.
              bind-key -n C-. send-keys C-.
              bind-key -T copy-mode-vi v send-keys -X begin-selection
              bind-key -T copy-mode-vi y send-keys -X copy-selection

              # tmux-resurrect: also snapshot the rendered scrollback per pane
              set -g @resurrect-capture-pane-contents 'on'
              set -g @resurrect-strategy-nvim 'session'
              # Claude is intentionally NOT in @resurrect-processes; the
              # tmux-claude-resurrect post-restore hook re-runs it with --resume.
              set -g @resurrect-processes 'ssh'

              # tmux-continuum: auto-save every 15 min, restore on server start
              set -g @continuum-restore 'on'
              set -g @continuum-save-interval '15'

              # Load continuum LAST, after status-right and the @continuum-* options
              # above are set. continuum prepends its auto-save interpolation onto
              # the current status-right at load, so it must run after we set it.
              run-shell ${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux
            '';
        };
      };
    };
}
