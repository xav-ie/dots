# `git wt` subcommand. Everything else about worktrunk (package, settings, shell
# integrations) comes from home-manager's own `programs.worktrunk` module.
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
      config = lib.mkIf (cfg.enable && cfg.package != null) {
        home.packages = [
          (pkgs.runCommand "git-wt" { } ''
            mkdir -p "$out/bin"
            ln -s ${lib.getExe cfg.package} "$out/bin/git-wt"
          '')
        ];
      };
    };
}
