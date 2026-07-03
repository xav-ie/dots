# Consumes the browser-session-mcp flake's NixOS module (Chrome + the
# listener/reaper/takeover daemons) and layers on the praesidium-specific bits:
# the NVIDIA GPU Chrome flags and the Traefik/mcp-proxy routing. The MCP server
# itself runs in the mcp-proxy container (see _mcp-proxy/servers/browser-session).
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
      inherit (config.services.local-networking) baseDomain;
      cfg = config.services.browser-session;
    in
    {
      imports = [ inputs.browser-session-mcp.nixosModules.default ];

      # Exposure is a dots concern, not the upstream module's: declare the
      # subdomains here so Traefik (nginx.nix) and the mcp-proxy server module
      # route against one source of truth.
      options.services.browser-session = {
        chrome.subdomain = lib.mkOption {
          type = lib.types.str;
          default = "chrome";
          description = "Subdomain Traefik routes to the Chrome DevTools endpoint.";
        };
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

          chrome = {
            package = pkgs.pkgs-mine.chrome-headless-shell;
            # Real-GPU WebGL via ANGLE-over-Vulkan on the NVIDIA driver: the
            # renderer string stays genuine (a software-GL spoof gets flagged for
            # inconsistency). Vulkan initializes headlessly — the GL/GLX path
            # fails with "Could not open the default X display".
            extraArgs = [
              "--use-gl=angle"
              "--use-angle=vulkan"
              "--enable-features=Vulkan"
              "--ozone-platform=headless"
              "--ignore-gpu-blocklist"
            ];
            environment = {
              LD_LIBRARY_PATH = "/run/opengl-driver/lib:${pkgs.vulkan-loader}/lib";
              VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
            };
          };

          # Agent sessions go idle between runs but shouldn't pin a core
          # overnight — reap sooner than the 24h upstream default.
          reaper.maxIdleHours = 2;

          # The takeover page's browser connects straight to Chrome over the
          # public chrome.<base> route (TLS-terminated by Traefik).
          takeover.chromeWsBase = "wss://${cfg.chrome.subdomain}.${baseDomain}";
        };

        services.local-networking.subdomains = [
          cfg.chrome.subdomain
          cfg.takeover.subdomain
        ];
      };
    };
}
