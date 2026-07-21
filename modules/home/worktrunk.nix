{
  flake.modules.homeManager.common =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.worktrunk;
    in
    {
      options.programs.worktrunk = {
        enable = lib.mkEnableOption "worktrunk (wt) - git worktree management for parallel AI agent workflows";

        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.pkgs-bleeding.worktrunk;
          defaultText = lib.literalExpression "pkgs.pkgs-bleeding.worktrunk";
          description = "The worktrunk package to use";
        };

        enableNushellIntegration = lib.mkOption {
          type = lib.types.bool;
          default = config.programs.nushell.enable;
          defaultText = lib.literalExpression "config.programs.nushell.enable";
          description = "Whether to enable nushell integration (wrapper function + completions)";
        };

        enableGitSubcommand = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to install a git-wt subcommand so `git wt` invokes worktrunk";
        };
      };

      config = lib.mkIf cfg.enable {
        home.packages = [
          cfg.package
        ]
        ++ lib.optional cfg.enableGitSubcommand (
          pkgs.runCommand "git-wt" { } ''
            mkdir -p "$out/bin"
            ln -s ${cfg.package}/bin/wt "$out/bin/git-wt"
          ''
        );

        programs.nushell.extraConfig = lib.mkIf cfg.enableNushellIntegration ''
          source ${
            pkgs.runCommand "worktrunk-nushell-integration.nu" { } ''
              ${cfg.package}/bin/wt config shell init nu > "$out"
            ''
          }
        '';
      };
    };
}
