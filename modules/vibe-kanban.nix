# A user service because the agents it spawns need the user's PATH, git identity
# and repos. PORT pins the listener, which is otherwise auto-assigned.
{
  flake.modules = {
    homeManager.linux =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.services.vibe-kanban;
      in
      {
        options.services.vibe-kanban = {
          port = lib.mkOption {
            type = lib.types.port;
            default = 38976;
            description = "Loopback port the board listens on.";
          };
        };

        config = {
          # herdr-edit backs the board's "Custom" editor setting: it opens a
          # task's worktree in a new herdr workspace running nvim.
          home.packages = [
            pkgs.pkgs-mine.herdr-edit
            pkgs.pkgs-mine.vibe-kanban
          ];

          systemd.user.services.vibe-kanban = {
            Unit = {
              Description = "Vibe Kanban agent board";
              After = [ "network.target" ];
            };
            Service = {
              ExecStart = lib.getExe pkgs.pkgs-mine.vibe-kanban;
              # ponytail: the second "preview proxy" port stays local and
              # unrouted; pin and proxy it too if previews are ever wanted.
              Environment = [
                "PORT=${toString cfg.port}"
                "HOST=127.0.0.1"
              ];
              Restart = "always";
              RestartSec = 5;
            };
            Install.WantedBy = [ "default.target" ];
          };
        };
      };

    nixos.praesidium =
      { config, ... }:
      {
        services.local-networking.proxies.vibe-kanban = {
          subdomain = "vibe-kanban";
          inherit (config.home-manager.users.${config.defaultUser}.services.vibe-kanban) port;
        };
      };
  };
}
