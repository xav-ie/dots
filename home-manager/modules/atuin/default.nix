{ pkgs, ... }:
{
  config = {
    programs.atuin = {
      enable = true;
      # super buggy on macos
      daemon.enable = pkgs.stdenv.isLinux;
      enableZshIntegration = false;
      # https://docs.atuin.sh/configuration/config
      settings = {
        style = "compact";
        show_tabs = false;
        workspaces = true;
      };
    };
  };
}
