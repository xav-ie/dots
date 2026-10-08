{
  flake.modules.homeManager.common =
    { lib, pkgs, ... }:
    let
      pueueDaemon = lib.getExe' pkgs.pueue "pueued";
    in
    {
      config = {
        home.packages = [
          pkgs.pueue
        ];

        services.pueue = {
          enable = pkgs.stdenv.hostPlatform.isLinux;
        };

        launchd.agents.pueueDaemon = {
          enable = pkgs.stdenv.hostPlatform.isDarwin;
          config = {
            Debug = true;
            Program = pueueDaemon;
            KeepAlive = true;
            RunAtLoad = true;
            StandardOutPath = "/tmp/pueueDaemon.log";
            StandardErrorPath = "/tmp/pueueDaemon.err";
          };
        };
      };
    };
}
