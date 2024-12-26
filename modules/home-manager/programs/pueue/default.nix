{ pkgs, ... }:
let
  pueueDaemon = pkgs.writeShellScript "pueue-daemon" ''
    ${pkgs.pueue}/bin/pueued 
  '';
in
{
  config = {
    home.packages = [
      pkgs.pueue
    ];
    home.file.".config/pueue/pueue.yml".source = ./pueue.yml;

    services.pueue = {
      enable = pkgs.stdenv.isLinux;
    };

    launchd.agents.pueueDaemon = {
      enable = pkgs.stdenv.isDarwin;
      config = {
        Debug = true;
        Program = "${pueueDaemon}";
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/pueueDaemon.log";
        StandardErrorPath = "/tmp/pueueDaemon.err";
      };
    };
  };
}
