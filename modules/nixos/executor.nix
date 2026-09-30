{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config) defaultUser;
      cfg = config.services.executor;
      userHome = "/home/${defaultUser}";
      executorWorkspace = "/var/lib/executor-web";

      # Boot readiness gate. `after = podman-mcp.service` only waits for the
      # container to launch — mcp-proxy still needs a few seconds to set up its
      # servers and be routed by traefik. executor's config-sync probes each
      # source once and gives up on failure, so without this a boot leaves every
      # source with an empty tool manifest until a manual `restart executor-web`.
      # Poll mcp-proxy's server-agnostic `/status` endpoint (200 once its HTTP
      # server is up and traefik routes it) rather than any named server. Exit 0
      # on timeout so executor still starts instead of hanging the boot.
      waitForMcpProxy = pkgs.writeShellScript "executor-wait-mcp-proxy" ''
        url="https://mcp.${config.services.local-networking.baseDomain}/status"
        for i in $(seq 1 90); do
          code=$(${pkgs.curl}/bin/curl -sk -m 3 -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || true)
          [ "$code" = "200" ] && { echo "mcp-proxy ready after $(( (i - 1) * 2 ))s"; exit 0; }
          sleep 2
        done
        echo "mcp-proxy not ready after 180s; starting executor anyway" >&2
        exit 0
      '';

      # State lives in three places: sources/connections/OAuth clients in the db,
      # the secret values they reference in auth.json, and the source list in
      # executor.jsonc. secrets/executor.json is a sops-encrypted tar of all three.
      stateDb = "${userHome}/.executor/data.db";
      stateAuth = "${userHome}/.local/share/executor/auth.json";
      stateJsonc = "${executorWorkspace}/executor.jsonc";

      # A fresh machine (no db) is restored from the backup. Restoring only into
      # an empty state keeps a reset or a newer local state from being clobbered.
      restoreState = pkgs.writeShellScript "executor-restore" ''
        set -eu
        [ -e ${stateDb} ] && exit 0
        tmp=$(${pkgs.coreutils}/bin/mktemp -d)
        trap '${pkgs.coreutils}/bin/rm -rf "$tmp"' EXIT
        ${pkgs.gnutar}/bin/tar -C "$tmp" -I ${pkgs.zstd}/bin/zstd -xf ${config.sops.secrets.executor-backup.path}
        ${pkgs.coreutils}/bin/install -Dm600 "$tmp/data.db" ${stateDb}
        ${pkgs.coreutils}/bin/install -Dm600 "$tmp/auth.json" ${stateAuth}
        ${pkgs.coreutils}/bin/install -Dm644 "$tmp/executor.jsonc" ${stateJsonc}
        echo "restored executor state from backup"
      '';

      # Rewrites secrets/executor.json in the dots checkout when the fingerprint
      # changes. OAuth access tokens and health/sync timestamps churn constantly,
      # so they are left out of the fingerprint; the file is left uncommitted.
      backupState = pkgs.writeShellApplication {
        name = "executor-backup";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnutar
          pkgs.jq
          pkgs.sops
          pkgs.sqlite
          pkgs.zstd
        ];
        text = # sh
          ''
            repo=${userHome}/Projects/dots
            stamp=${userHome}/.local/state/executor-backup.sha256
            [ -d "$repo/secrets" ] || exit 0
            sum=$( {
              cat ${stateJsonc}
              jq -S 'with_entries(select((.key | startswith("oauth:")) and (.key | endswith(":refresh") | not) | not))' ${stateAuth}
              sqlite3 -readonly ${stateDb} ${lib.escapeShellArg ''
                select slug, plugin_id, name, description, config from integration order by slug;
                select integration, name, template, provider, item_ids, identity_label, oauth_client, oauth_scope from connection order by integration, name;
                select slug, authorization_url, token_url, grant, client_id, client_secret_item_id, resource from oauth_client order by slug;
                select id, pattern, action, position from tool_policy order by id;
              ''}
            } | sha256sum | cut -d' ' -f1)
            [ "$sum" = "$(cat "$stamp" 2>/dev/null || true)" ] && exit 0
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' EXIT
            sqlite3 -readonly ${stateDb} ".backup $tmp/data.db"
            cp ${stateAuth} ${stateJsonc} "$tmp"
            tar -C "$tmp" --zstd -cf "$tmp/state.tar.zst" data.db auth.json executor.jsonc
            cd "$repo"
            sops -e --input-type binary --output-type json --filename-override secrets/executor.json "$tmp/state.tar.zst" > "$tmp/executor.json"
            mv "$tmp/executor.json" secrets/executor.json
            mkdir -p "$(dirname "$stamp")"
            echo "$sum" > "$stamp"
            echo "wrote $repo/secrets/executor.json"
          '';
      };
    in
    {
      options.services.executor = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to enable the Executor web service";
        };
        subdomain = lib.mkOption {
          type = lib.types.str;
          default = "executor";
          description = "The subdomain for Executor";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 38972;
          description = "Port for the Executor web server (opencode port + 1)";
        };
      };

      config = lib.mkIf cfg.enable {
        # Register subdomain
        services.local-networking.proxies.executor = { inherit (cfg) subdomain port; };

        # Create workspace directory
        systemd.tmpfiles.rules = [
          "d ${executorWorkspace} 0755 ${defaultUser} users - -"
        ];

        # Main executor web service
        systemd.services.executor-web = {
          description = "Executor web server";
          after = [
            "network.target"
            "podman-mcp.service"
          ];
          wantedBy = [ "multi-user.target" ];
          # Intentionally no `partOf`/`bindsTo` on podman-mcp: with stateless
          # streamable HTTP, proxy restarts are transparent. Cascading a restart
          # here would re-run config-sync before the new proxy is listening,
          # leaving sources with empty tool manifests until a manual re-probe.

          environment = {
            HOME = userHome;
            # Lets the daemon reclaim a stale server.json from a previous boot
            # instead of refusing to start and crash-looping under Restart.
            EXECUTOR_SUPERVISED = "1";
            # Search -> tool-call events for search evals (~/Projects/snippet-evals/usage.py).
            EXECUTOR_USAGE_LOG = "${executorWorkspace}/usage.jsonl";
            # Local embedding server for hybrid tools.search; keyword-only when down.
            EXECUTOR_EMBED_URL = "http://127.0.0.1:38978/v1/embeddings";
          };

          serviceConfig = {
            User = defaultUser;
            WorkingDirectory = executorWorkspace;
            # Gate config-sync on the proxy being reachable (see waitForMcpProxy).
            ExecStartPre = [
              restoreState
              waitForMcpProxy
            ];
            ExecStart = "${pkgs.pkgs-mine.executor}/bin/executor daemon run --foreground --port ${cfg.port |> toString} --allowed-host ${cfg.subdomain}.${config.services.local-networking.baseDomain}";
            Restart = "on-failure";
            RestartSec = 5;
            StandardOutput = "journal";
            StandardError = "journal";
            SyslogIdentifier = "executor-web";
          };
        };

        sops.secrets.executor-backup = {
          sopsFile = ../../secrets/executor.json;
          format = "binary";
          owner = defaultUser;
        };

        systemd.services.executor-backup = {
          description = "Back up executor state into the dots repo";
          after = [ "executor-web.service" ];
          serviceConfig = {
            Type = "oneshot";
            User = defaultUser;
            ExecStart = lib.getExe backupState;
          };
        };

        systemd.timers.executor-backup = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "hourly";
            Persistent = true;
          };
        };
      };
    };
}
