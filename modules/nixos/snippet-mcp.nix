{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.snippet-mcp;
      # Lives in the dots repo, age-encrypted, so snippets survive a wipe once
      # committed. Commits are left to the user.
      snippetsDir = "${config.programs.nh.flake}/snippets";
    in
    {
      options.services.snippet-mcp = {
        enable = lib.mkEnableOption "the snippet-mcp service" // {
          default = true;
        };

        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "snippets";
          description = "Subdomain under services.local-networking.baseDomain (Traefik route).";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 38974;
          description = "HTTP listen port. Picked just above executor (38972) and opencode (38971).";
        };

      };

      config = lib.mkIf cfg.enable {
        # Rides on the shared mcp.<base> host alongside the containerised
        # mcp-proxy, so this route is a path match rather than a host match.
        services.local-networking.proxies.snippets-via-mcp = {
          inherit (cfg) port;
          rule = "Host(`mcp.${config.services.local-networking.baseDomain}`) && PathPrefix(`/snippets`)";
          # Beats the docker-provider router on bare Host(`mcp.<base>`)
          # regardless of rule-length math.
          priority = 100;
          middlewares = [ "snippets-strip-prefix" ];
        };

        systemd.services.snippet-mcp = {
          description = "snippet-mcp HTTP MCP server";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network.target"
            "sops-install-secrets.service"
          ];

          # EXECUTOR_BASE_URL/EXECUTOR_AUTH_TOKEN_FILE/EXECUTOR_REFRESH_NAMESPACE
          # drove a POST to v1's /api/connections/.../refresh after
          # save/update/delete; v2 has no such endpoint, and its tool listings
          # refresh on their own within EXECUTOR_TOOL_LISTING_FRESH_SECONDS
          # (default 30s), so snippet-mcp just degrades to that instead.
          environment = {
            SNIPPET_DIR = snippetsDir;
            # Code snippets run through executor's execute and return results
            # (v2's sandbox can't run returned code). The bearer is the
            # EXECUTOR_AUTH_TOKEN line of the runtime-decrypted shell-env.
            EXECUTOR_URL = "http://127.0.0.1:${toString config.services.executor.port}";
            EXECUTOR_ENV_FILE = "/run/secrets/shell-env";
            SNIPPET_AGE_KEY_FILE = "%d/age-key";
            RUST_LOG = "snippet_mcp=info,rmcp=warn";
          };

          serviceConfig = {
            ExecStart = lib.escapeShellArgs [
              "${pkgs.pkgs-mine.snippet-mcp}/bin/snippet-mcp"
              "--mode"
              "http"
              "--port"
              (cfg.port |> toString)
              "--host"
              "127.0.0.1"
              "--allowed-host"
              "mcp.${config.services.local-networking.baseDomain}"
            ];
            # The user owns the repo checkout, so saved files stay committable.
            User = config.defaultUser;
            # The sops age key (root-only) decrypts and encrypts snippets.
            # systemd hands the service a private copy under
            # $CREDENTIALS_DIRECTORY. No executor-auth credential anymore:
            # the v1-only refresh call that used it is gone (see above).
            LoadCredential = [
              "age-key:${config.sops.age.keyFile}"
            ];
            Restart = "on-failure";
            RestartSec = 5;
            StandardOutput = "journal";
            StandardError = "journal";
            SyslogIdentifier = "snippet-mcp";

            # Hardening — service only needs its snippets dir and outbound HTTPS
            # to executor. Home is an empty tmpfs with just that dir bound in.
            ProtectSystem = "strict";
            ProtectHome = "tmpfs";
            BindPaths = [ snippetsDir ];
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            PrivateTmp = true;
            PrivateDevices = true;
            NoNewPrivileges = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            SystemCallArchitectures = "native";
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
          };
        };
      };
    };
}
