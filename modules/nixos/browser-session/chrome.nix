{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.chrome-headless;
    in
    {
      options.services.chrome-headless = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Run a persistent headless Chrome exposing the DevTools Protocol.";
        };
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "chrome";
          description = "Subdomain for the DevTools HTTP/WS endpoint (under services.local-networking.baseDomain).";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 9222;
          description = "Local DevTools port bound to 127.0.0.1.";
        };
        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/chrome";
          description = "Chrome user-data-dir. Persists cookies/storage across Chrome restarts.";
        };
      };

      config = lib.mkIf cfg.enable {
        services.local-networking.subdomains = [ cfg.subdomain ];

        users.users.chrome-headless = {
          isSystemUser = true;
          group = "chrome-headless";
          home = cfg.dataDir;
          createHome = false;
        };
        users.groups.chrome-headless = { };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0750 chrome-headless chrome-headless - -"
        ];

        # Chrome binds DevTools to 127.0.0.1 only — Chrome rejects non-loopback
        # Host headers as DNS-rebinding protection. Traefik (see nginx.nix) rewrites
        # the public Host header to `localhost` before forwarding here.
        systemd.services.chrome-headless = {
          description = "Persistent headless Chrome for automation";
          after = [ "network.target" ];
          wantedBy = [ "multi-user.target" ];

          # Render WebGL on the real NVIDIA GPU so the renderer string is
          # genuine (a software-GL spoof gets flagged for inconsistency). The
          # NVIDIA device nodes are world-accessible; point the loader + glvnd
          # at the driver in /run/opengl-driver.
          environment = {
            # libvulkan loader + NVIDIA driver libs; point the loader at the
            # NVIDIA Vulkan ICD. ANGLE renders WebGL via Vulkan, which works
            # headlessly on NVIDIA (no X server — unlike the GL/GLX backend).
            LD_LIBRARY_PATH = "/run/opengl-driver/lib:${pkgs.vulkan-loader}/lib";
            VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
          };

          serviceConfig = {
            Type = "simple";
            User = "chrome-headless";
            Group = "chrome-headless";
            WorkingDirectory = cfg.dataDir;
            Restart = "on-failure";
            RestartSec = 5;
            ExecStart =
              [
                "${pkgs.pkgs-mine.chrome-headless-shell}/bin/chrome-headless-shell"
                "--no-sandbox"
                "--disable-dev-shm-usage"
                # Real GPU WebGL via ANGLE-over-Vulkan on the NVIDIA driver.
                # Vulkan initializes headlessly (no X server); the GL/GLX path
                # fails with "Could not open the default X display". The
                # renderer is then the genuine NVIDIA string, which passes the
                # consistency checks a software-GL spoof fails.
                "--use-gl=angle"
                "--use-angle=vulkan"
                "--enable-features=Vulkan"
                "--ozone-platform=headless"
                "--ignore-gpu-blocklist"
                "--user-data-dir=${cfg.dataDir}"
                "--remote-debugging-address=127.0.0.1"
                "--remote-debugging-port=${cfg.port |> toString}"
                # Pass Chrome's Origin check for WebSocket upgrades from Traefik.
                "--remote-allow-origins=*"
                # Don't advertise automation: drops `navigator.webdriver=true` and
                # the automation blink features that bot-detectors key on.
                "--disable-blink-features=AutomationControlled"
                # Realistic laptop window/screen size (a headless default or
                # odd size is itself a fingerprint tell). 1920x1080 @ DPR 1.
                "--window-size=1920,1080"
              ]
              |> lib.concatStringsSep " ";
          };
        };
      };
    };
}
