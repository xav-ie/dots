{ pkgs, ... }:
{
  config = {
    programs.atuin = {
      enable = true;
      package = pkgs.pkgs-bleeding.atuin;
      # super buggy on macos
      daemon.enable = pkgs.stdenv.isLinux;
      enableZshIntegration = false;
      enableNushellIntegration = false;
      # https://docs.atuin.sh/configuration/config
      settings = {
        style = "compact";
        show_tabs = false;
        workspaces = true;
      };
    };
  };
}
