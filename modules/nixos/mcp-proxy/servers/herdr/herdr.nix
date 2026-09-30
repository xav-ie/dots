{
  flake.modules.nixos.praesidium =
    { config, pkgs, ... }:
    let
      home = "/home/${config.defaultUser}";
      server = pkgs.writers.writePython3Bin "herdr-mcp" {
        libraries = [ pkgs.python3Packages.mcp ];
        flakeIgnore = [ "E501" ];
      } (builtins.readFile ./server.py);
    in
    {
      services.mcp-proxy.servers.herdr = {
        command = "${server}/bin/herdr-mcp";
        packages = [ server ];
        envVars = {
          HERDR_HOME = home;
          HERDR_SOCKET_PATH = "/run/herdr/herdr.sock";
        };
        # The directory, not the socket file, so a restarted herdr server's
        # fresh socket is still visible. Read-only keeps backends from writing
        # herdr plugins/config; connect() still works on a read-only mount.
        # Root in the container passes the socket's 0600 check.
        volumes = [ "${home}/.config/herdr:/run/herdr:ro" ];
      };
    };
}
