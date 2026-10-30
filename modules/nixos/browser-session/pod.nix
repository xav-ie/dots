# Consumes the browser-session-mcp flake's NixOS module for its options, user
# and state dirs, but runs the stack as containers in one podman pod instead of
# its host units: Chrome (chrome.nix) and the MCP server plus its daemons
# (server.nix). Chrome's DevTools port has no auth and binds the pod's loopback,
# so only browser-session's own code can reach it: not the host, not the mcp
# container's other servers, not any other container.
{
  flake.modules.nixos.praesidium =
    {
      inputs,
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.browser-session;
      gpu = import ../../_lib/gpu.nix;
      podman = lib.getExe pkgs.podman;
    in
    {
      imports = [ inputs.browser-session-mcp.nixosModules.default ];

      options.services.browser-session = {
        pod = lib.mkOption {
          type = lib.types.str;
          default = "browser-session";
          description = "Podman pod the Chrome and browser-session containers share.";
        };
        # Exposure is a dots concern, not the upstream module's.
        takeover.subdomain = lib.mkOption {
          type = lib.types.str;
          default = "chrome-takeover";
          description = "Subdomain Traefik routes to the takeover daemon.";
        };
      };

      config = {
        services.browser-session = {
          enable = true;
          package = pkgs.pkgs-mine.browser-session-mcp;
          # The containers replace the upstream host units.
          systemd.enable = false;

          chrome = {
            # Branded Chrome in new headless mode: its plugins, window.chrome and
            # Client Hints are the real ones, which is what lets bot-managed
            # logins (Verizon's Akamai) load; chrome-headless-shell gets 418s.
            package = pkgs.google-chrome;
            executable = "google-chrome-stable";
            # Real-GPU WebGL via ANGLE-over-Vulkan on the NVIDIA driver: the
            # renderer string stays genuine (a software-GL spoof gets flagged for
            # inconsistency). Vulkan initializes headlessly; the GL/GLX path
            # fails with "Could not open the default X display".
            extraArgs = [
              "--headless"
              "--use-gl=angle"
              "--use-angle=vulkan"
              "--enable-features=Vulkan"
              "--ozone-platform=headless"
              "--ignore-gpu-blocklist"
            ];
            # /run/opengl-driver is mounted into the container by the NVIDIA CDI
            # device (chrome.nix).
            environment = {
              LD_LIBRARY_PATH = "/run/opengl-driver/lib:${pkgs.vulkan-loader}/lib";
              VK_ICD_FILENAMES = gpu.vulkanIcd;
            };
          };

          # Bound inside the pod's network namespace only; Traefik reaches it
          # there (server.nix).
          takeover.address = "0.0.0.0";

          # Agent sessions go idle between runs but shouldn't pin a core
          # overnight; reap sooner than the 24h upstream default.
          reaper.maxIdleHours = 2;
        };

        # Pinned to the ids first allocated, which own the existing profile in
        # chrome.dataDir; the container runs Chrome under them numerically.
        users.users.chrome-headless.uid = 985;
        users.groups.chrome-headless.gid = 981;

        # Recreated on every start so a change to the flags below takes effect;
        # the containers are PartOf this unit and restart with it.
        systemd.services.browser-session-pod = {
          after = [ "podman.service" ];
          requires = [ "podman.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStop = "${podman} pod rm --force --ignore ${cfg.pod}";
          };
          script = ''
            ${podman} pod rm --force --ignore ${cfg.pod}
            ${podman} pod create --name ${cfg.pod}
          '';
        };
      };
    };
}
