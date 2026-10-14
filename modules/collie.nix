# Collie — the other phone UI for the herd.
#
# bridge/config.ts reads every setting from process.env, so the unit is the
# whole configuration: no .env file, and none of upstream's collie-ctl.sh, which
# would otherwise own the build, the service and the front door.
{
  # Web Push (VAPID) keys; generate them with `just collie-vapid`. Without them
  # the bridge runs with push disabled.
  flake.modules.nixos.linux =
    { config, ... }:
    {
      sops = {
        secrets = {
          "collie/vapid_private" = { };
          "collie/vapid_public" = { };
        };
        templates."collie.env" = {
          owner = config.defaultUser;
          content = ''
            COLLIE_VAPID_PRIVATE=${config.sops.placeholder."collie/vapid_private"}
            COLLIE_VAPID_PUBLIC=${config.sops.placeholder."collie/vapid_public"}
          '';
        };
      };
    };

  flake.modules.homeManager.linux =
    {
      config,
      fonts,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      cfg = config.services.collie;
      # Shared by the unit and the `collie` CLI, so `collie pair` prints the
      # public URL and talks to the same port as the bridge.
      env = {
        COLLIE_ALLOWED_ORIGINS = cfg.origin;
        COLLIE_HOST = "127.0.0.1";
        COLLIE_PORT = toString cfg.port;
        # Host allowlist, which defeats DNS rebinding against a loopback
        # bridge. Same value, without the scheme.
        COLLIE_PUBLIC_HOSTS = lib.removePrefix "https://" cfg.origin;
        COLLIE_PUBLIC_URL = cfg.origin;
        COLLIE_VAPID_SUBJECT = cfg.origin;
        # The bridge defaults to ~/.config/collie but the CLI to herdr's
        # plugin dir; pin both to the one home-manager writes.
        HERDR_PLUGIN_CONFIG_DIR = "${config.xdg.configHome}/collie";
      };
      toml = pkgs.formats.toml { };
    in
    {
      options.services.collie = {
        origin = lib.mkOption {
          type = lib.types.str;
          default = "https://collie.lalala.casa";
          description = ''
            Public origin, as a full origin. The bridge is same-origin only, so
            this must match the tunnel's published hostname or the page loads
            and stays empty.
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 38977;
          description = "Loopback port the bridge listens on.";
        };
      };

      config = {
        # A wrapper rather than makeWrapper: the binary finds its install root
        # through the realpath of argv0, which a renamed .collie-wrapped breaks.
        home.packages = [
          (pkgs.writeShellScriptBin "collie" ''
            ${lib.toShellVars env}
            export ${lib.concatStringsSep " " (lib.attrNames env)}
            exec ${lib.getExe pkgs.collie} "$@"
          '')
        ];

        xdg.configFile = {
          # The font check resolves symlinks against the resolved fonts/ dir, so
          # the dir itself must be the store link; per-file links get refused.
          # The face dresses Collie's chrome only, never the pane mirror.
          "collie/fonts".source =
            pkgs.runCommand "collie-fonts"
              {
                nativeBuildInputs = [
                  pkgs.python3Packages.fonttools
                  pkgs.python3Packages.brotli
                ];
              }
              ''
                mkdir $out
                fonttools ttLib.woff2 compress \
                  -o $out/sans.woff2 ${fonts.package "sans"}/share/fonts/truetype/InterVariable.ttf
              '';
          "collie/launchers.toml".source = toml.generate "launchers.toml" {
            launchers = [
              {
                command = "claude";
                cwd = "~";
                label = "Claude";
              }
              {
                command = "opencode";
                cwd = "~";
                label = "OpenCode";
              }
            ];
          };
          "collie/theme.toml".source = toml.generate "theme.toml" {
            font = [
              {
                family = fonts.name "sans";
                file = "sans.woff2";
                weight = "100 900";
              }
            ];
          };
        };

        systemd.user.services.collie = {
          Unit = {
            Description = "Collie bridge";
            # Collie re-reads its TOML on an mtime change, and every store file's
            # mtime is 1, so a rebuild goes unnoticed without a restart.
            X-Restart-Triggers = map (f: config.xdg.configFile.${f}.source) [
              "collie/fonts"
              "collie/launchers.toml"
              "collie/theme.toml"
            ];
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = "${lib.getExe pkgs.collie} _exec-bridge";
            Environment = lib.mapAttrsToList (k: v: "${k}=${v}") env ++ [
              "PATH=${
                lib.makeBinPath [
                  pkgs.git
                  pkgs.herdr
                ]
              }"
            ];
            EnvironmentFile = osConfig.sops.templates."collie.env".path;
            Restart = "on-failure";
            RestartSec = 10;
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}
