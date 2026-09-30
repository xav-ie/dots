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

        executorBaseUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default =
            if config.services.executor.enable then
              "https://${config.services.executor.subdomain}.${config.services.local-networking.baseDomain}"
            else
              null;
          defaultText = lib.literalExpression ''"https://''${services.executor.subdomain}.''${baseDomain}" when executor is enabled, else null'';
          example = "https://executor.lalala.casa";
          description = ''
            Base URL of the executor host. When set, snippet-mcp dynamically
            discovers the workspace scope id (workspace-specific, not stable
            across recreations) and POSTs a refresh after save/update/delete so
            executor re-probes its catalogue without a restart. Set to null to
            skip the refresh; the service degrades gracefully.
          '';
        };

        executorRefreshNamespace = lib.mkOption {
          type = lib.types.str;
          default = "snippets";
          description = ''
            Namespace executor uses for the snippets source (the `namespace` field
            in `executor.jsonc`). Sent in the refresh POST body.
          '';
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
          after = [ "network.target" ];

          environment = {
            SNIPPET_DIR = snippetsDir;
            SNIPPET_AGE_KEY_FILE = "%d/age-key";
            RUST_LOG = "snippet_mcp=info,rmcp=warn";
            EXECUTOR_REFRESH_NAMESPACE = cfg.executorRefreshNamespace;
          }
          // lib.optionalAttrs (cfg.executorBaseUrl != null) {
            EXECUTOR_BASE_URL = cfg.executorBaseUrl;
            EXECUTOR_AUTH_TOKEN_FILE = "%d/executor-auth";
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
            # The sops age key (root-only) decrypts and encrypts snippets;
            # executor's bearer token is owned by the executor user. systemd
            # hands the service private copies under $CREDENTIALS_DIRECTORY.
            LoadCredential = [
              "age-key:${config.sops.age.keyFile}"
            ]
            ++ lib.optional (
              cfg.executorBaseUrl != null
            ) "executor-auth:/home/${config.defaultUser}/.executor/server-control/auth.json";
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
