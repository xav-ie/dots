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
      enable = pkgs.stdenv.isLinux;
    };

    launchd.agents.pueueDaemon = {
      enable = pkgs.stdenv.isDarwin;
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
}
