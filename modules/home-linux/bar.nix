{
  flake.modules.homeManager.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hyprCfg = config.programs.hyprland;
    in
    {
      options.programs.ags-bar = {
        barHeight = lib.mkOption {
          # The height of the bar's layer-shell surface, in px. Hyprland uses this
          # to offset *floating* windows (e.g. PIP) below the bar — tiled windows
          # already avoid it via the bar's EXCLUSIVE exclusive zone. Verify the real
          # value after a switch:
          # > hyprctl layers -j | jq '.. | objects | select(.namespace? == "bar") | .h'
          # and adjust the base below if it differs.
          default = 30 + hyprCfg.borderSizeNumeric * 2 + 1;
          type = lib.types.ints.positive;
        };
      };

      config = {
        home.packages = [ pkgs.pkgs-mine.bar ];

        # AstalWireplumber binds the default sink on startup, and wireplumber.service
        # being `started` doesn't mean a default sink exists yet. Block startup until
        # `wpctl` reports one (capped ~30s, fail-open) so the volume module doesn't
        # come up on a phantom node.
        systemd.user.services.bar = {
          Unit = {
            Description = "AGS status bar";
            PartOf = [ "graphical-session.target" ];
            # The notifications module runs `notifctl -swb`, which connects to the
            # notification daemon as a proxy. Order after it so the daemon owns the
            # bus name first (otherwise the proxy would grab it and run headless).
            Wants = [ "notification-center.service" ];
            After = [
              "graphical-session.target"
              "notification-center.service"
              "pipewire.service"
              "wireplumber.service"
            ];
          };
          Service = {
            ExecStartPre =
              pkgs.writeShellScript "bar-wait-default-sink" # sh
                ''
                  for _ in $(seq 1 150); do
                    if ${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@ >/dev/null 2>&1; then
                      exit 0
                    fi
                    sleep 0.2
                  done
                  # Fail-open: start the bar even if no default sink ever appears.
                  exit 0
                '';
            ExecStart = "${pkgs.pkgs-mine.bar}/bin/bar";
            Restart = "on-failure";
            # Soft backstop against runaway growth: the kernel reclaims this
            # cgroup's pages once it crosses the threshold instead of letting it
            # balloon and swap-thrash the session. A healthy bar sits well under
            # this, so it should never bite in normal operation.
            MemoryHigh = "512M";
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
      };
    };
}
