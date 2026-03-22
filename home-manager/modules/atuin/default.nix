{ pkgs, lib, ... }:
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

    # Source hex init before all other nushell config
    programs.nushell.extraConfig = lib.mkOrder 50 ''
      source ${
        pkgs.runCommand "atuin-hex-nushell-config.nu"
          {
            nativeBuildInputs = [ pkgs.writableTmpDirAsHomeHook ];
          }
          ''
            ${pkgs.atuin}/bin/atuin hex init nu >> "$out"
          ''
      }
    '';
  };
}
