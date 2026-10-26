{
  flake.modules.homeManager.common =
    { config, lib, ... }:
    let
      cfg = config.programs.fzf;
    in
    {
      config = {
        # fuzzy finder
        programs.fzf = {
          enable = true;
          # atuin owns Ctrl-R, so fzf's history widget stays unbound
          historyWidget.nushell.command = "";
          # HM's guard only checks the zle option, which stays on in `zsh -i -c`
          # without a terminal; fzf's script then fails restoring it with
          # "can't change option: zle" on stderr, polluting the output of tools
          # that run commands through an interactive shell (Dayflow).
          enableZshIntegration = false;
        };

        # Same slot as HM's integration, but also requires a terminal.
        programs.zsh.initContent = lib.mkOrder 910 ''
          if [[ $options[zle] = on && -n $TTY ]]; then
            source <(${lib.getExe cfg.package} --zsh)
          fi
        '';
      };
    };
}
