# Continuous SQLite replication for opencode's session database via litestream.
# V2 keeps all sessions in ~/.local/share/opencode/opencode.db (WAL mode), so
# claude's syncthing-the-JSON-tree approach cannot work here. Instead each
# machine streams its own WAL into a local replica directory and syncthing
# (folder id "opencode-replicas", wired in modules/home/syncthing.nix) carries
# both directories to the peer — per-host subdirectories, so there is no
# conflict surface, same property that makes the claude-projects folder safe.
#
# Recovery when a machine is down, from the SURVIVING machine:
#   litestream restore -o /tmp/recovered.db \
#     -from file://$HOME/.local/share/opencode/replicas/<dead-host>
# then either query /tmp/recovered.db directly, boot a scratch opencode
# against it, or (machine truly gone) stop opencode and adopt it as
# ~/.local/share/opencode/opencode.db. WAL is streamed continuously, so the
# recovery point is seconds, not a nightly snapshot.
{
  flake.modules.homeManager.common =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hostName = if pkgs.stdenv.hostPlatform.isDarwin then "nox" else "praesidium";

      litestreamConfig =
        pkgs.writeText "litestream-opencode.yml" # yaml
          ''
            dbs:
              - path: ${config.home.homeDirectory}/.local/share/opencode/opencode.db
                replicas:
                  - name: syncthing
                    type: file
                    path: ${config.home.homeDirectory}/.local/share/opencode/replicas/${hostName}
                    retention: 720h
                    retention-check-interval: 24h
                    sync-interval: 10s
          '';
    in
    {
      home.packages = [ pkgs.litestream ];

      # The peer's litestream writes into here over syncthing; ours writes the
      # sibling directory.
      home.file."./.local/share/opencode/replicas/.keep".text = "";

      systemd.user.services = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        opencode-litestream = {
          Unit = {
            Description = "Replicate opencode sessions to disk for cross-machine sync";
            After = [ "network-online.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe pkgs.litestream} replicate -config ${litestreamConfig}";
            Restart = "on-failure";
            RestartSec = 5;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };

      launchd.agents = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        opencode-litestream = {
          enable = true;
          config = {
            ProgramArguments = [
              (lib.getExe pkgs.litestream)
              "replicate"
              "-config"
              "${litestreamConfig}"
            ];
            KeepAlive = {
              Crashed = true;
              SuccessfulExit = false;
            };
            ProcessType = "Background";
            RunAtLoad = true;
          };
        };
      };
    };
}
