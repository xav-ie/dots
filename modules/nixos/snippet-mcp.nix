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
      workspace = "/var/lib/snippet-mcp";
      snippetsDir = "${workspace}/snippets";
      seedDir = "${pkgs.pkgs-mine.snippet-mcp}/share/snippet-mcp/seeds";
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
        users.groups.snippet-mcp = { };
        users.users.snippet-mcp = {
          isSystemUser = true;
          group = "snippet-mcp";
          home = workspace;
          createHome = false;
          description = "snippet-mcp service account";
        };

        # Workspace and snippets dir are restricted to the service user only.
        # Hand-edits require `sudo -u snippet-mcp $EDITOR ${snippetsDir}/<name>.md`.
        systemd.tmpfiles.rules = [
          "d ${workspace} 0700 snippet-mcp snippet-mcp - -"
          "d ${snippetsDir} 0700 snippet-mcp snippet-mcp - -"
        ];

        # Seed runtime snippets from the package's read-only seeds dir on every
        # activation, but never overwrite an existing file. `cp -n` is no-clobber;
        # the loop is idempotent and safe to re-run.
        systemd.services.snippet-mcp-seed = {
          description = "Seed snippet-mcp workspace from package defaults";
          wantedBy = [ "multi-user.target" ];
          before = [ "snippet-mcp.service" ];
          after = [ "systemd-tmpfiles-setup.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = "snippet-mcp";
            Group = "snippet-mcp";
            RemainAfterExit = true;
          };
          script = # sh
            ''
              set -eu
              for src in ${seedDir}/*.md; do
                [ -e "$src" ] || continue
                dest="${snippetsDir}/$(${pkgs.coreutils}/bin/basename "$src")"
                if [ ! -e "$dest" ]; then
                  ${pkgs.coreutils}/bin/cp "$src" "$dest"
                  ${pkgs.coreutils}/bin/chmod 0600 "$dest"
                fi
              done
            '';
        };

        systemd.services.snippet-mcp = {
          description = "snippet-mcp HTTP MCP server";
          wantedBy = [ "multi-user.target" ];
          after = [
            "network.target"
            "snippet-mcp-seed.service"
          ];
          requires = [ "snippet-mcp-seed.service" ];

          environment = {
            SNIPPET_DIR = snippetsDir;
            RUST_LOG = "snippet_mcp=info,rmcp=warn";
            EXECUTOR_REFRESH_NAMESPACE = cfg.executorRefreshNamespace;
          }
          // lib.optionalAttrs (cfg.executorBaseUrl != null) {
            EXECUTOR_BASE_URL = cfg.executorBaseUrl;
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
            User = "snippet-mcp";
            Group = "snippet-mcp";
            Restart = "on-failure";
            RestartSec = 5;
            StandardOutput = "journal";
            StandardError = "journal";
            SyslogIdentifier = "snippet-mcp";

            # Hardening — service only needs to read its own state dir and emit
            # outbound HTTPS to executor.
            ProtectSystem = "strict";
            ProtectHome = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectControlGroups = true;
            PrivateTmp = true;
            PrivateDevices = true;
            NoNewPrivileges = true;
            ReadWritePaths = [ snippetsDir ];
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
