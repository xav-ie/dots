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
          CLAUDE_PROJECTS_DIR = "/run/agent-sessions/claude";
          OPENCODE_DB = "/run/agent-sessions/opencode/opencode.db";
        };
        # The directory, not the socket file, so a restarted herdr server's
        # fresh socket is still visible. Read-only keeps backends from writing
        # herdr plugins/config; connect() still works on a read-only mount.
        # Root in the container passes the socket's 0600 check.
        # The agents' session stores, read-only, for last_response. opencode's
        # whole directory, since SQLite reads the db beside its -wal and -shm.
        volumes = [
          "${home}/.config/herdr:/run/herdr:ro"
          "${home}/.claude/projects:/run/agent-sessions/claude:ro"
          "${home}/.local/share/opencode:/run/agent-sessions/opencode:ro"
        ];
      };
    };
}
