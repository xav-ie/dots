{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config) defaultUser;
  cfg = config.services.opencode;
  userHome = "/home/${defaultUser}";
  cfgSecret = config.sops.placeholder;
in
{
  options.services.opencode = {
    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "opencode";
      description = "The subdomain for OpenCode";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 38971;
      description = "Port for the OpenCode web server";
    };
  };

  config = {
    sops = {
      secrets."opencode/password" = { };
      templates."opencode.env" = {
        owner = defaultUser;
        content = ''
          OPENCODE_SERVER_USERNAME=opencode
          OPENCODE_SERVER_PASSWORD=${cfgSecret."opencode/password"}
        '';
        restartUnits = [ "opencode-serve.service" ];
      };
    };

    services.local-networking.subdomains = [ cfg.subdomain ];

    # Runs as the default user so it has access to ~/.config/opencode,
    # ~/.local/share/opencode, API keys, and MCP servers.
    # Binds to 127.0.0.1 only -- Traefik handles external routing.
    systemd.services.opencode-serve = {
      description = "OpenCode web server";
      after = [
        "network.target"
        "podman-mcp.service"
      ];
      wantedBy = [ "multi-user.target" ];
      partOf = [ "podman-mcp.service" ];
      path = [
        pkgs.nodejs
        pkgs.pkgs-mine.mcp-sse-client
      ];
      environment = {
        HOME = userHome;
        MCP_SSE_DEBUG = "1";
      };
      serviceConfig = {
        User = defaultUser;
        ExecStart = "${userHome}/.npm/bin/opencode serve --hostname 127.0.0.1 --port ${toString cfg.port}";
        EnvironmentFile = config.sops.templates."opencode.env".path;
        Restart = "on-failure";
        RestartSec = 5;
        StandardOutput = "journal";
        StandardError = "journal";
        SyslogIdentifier = "opencode";
      };
    };
  };
}
