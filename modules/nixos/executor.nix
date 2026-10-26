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
      # v2's own default (apps/docs/content/run/cli.mdx); kept explicit so a
      # reinstall or a HOME change never silently moves the data directory.
      dataDir = "${userHome}/.executor/v2/cli";
      # /home itself is the btrfs subvolume (modules/nixos/hardware-configuration.nix's
      # @home), not userHome — a snapshot's source must be a subvolume root,
      # not an arbitrary directory inside one. Path within the snapshot is
      # relative to /home, e.g. "x/.executor/v2/cli".
      dataDirRelativeToHome = lib.removePrefix "/home/" dataDir;

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

      # tools.search reuses its stored rows of an app's tools for up to 24 h
      # unless the app's cache changes, and nothing evaluates an app when an
      # mcp-proxy backend adds or drops tools. Reading an app's tools evaluates
      # it, so do that for every app after the proxy starts. mcpRouter serves a
      # catalog fetched in the last 5 min as is (then 5 min stale while it
      # refetches), so a second pass after that window catches an app used just
      # before the restart.
      refreshToolIndex = pkgs.writeNuApplication {
        name = "executor-refresh-tools";
        text = # nu
          ''
            let api = "http://127.0.0.1:${toString cfg.port}"
            let token = open /run/secrets/shell-env | lines | where $it starts-with "EXECUTOR_AUTH_TOKEN=" | first | str replace "EXECUTOR_AUTH_TOKEN=" ""
            let headers = {Authorization: $"Bearer ($token)"}

            def list-apps [api: string, headers: record] {
              for _ in 1..90 {
                try { return (http get --max-time 10sec --headers $headers $"($api)/v1/apps") }
                sleep 2sec
              }
              error make {msg: "executor-refresh-tools: executor did not list its apps"}
            }

            def refresh [api: string, headers: record] {
              for app in (list-apps $api $headers) {
                let status = try {
                  http get --full --allow-errors --max-time 60sec --headers $headers $"($api)/v1/tools?app=($app.id)&limit=1" | get status
                } catch { "no answer" }
                if $status != 200 { print -e $"executor-refresh-tools: ($app.slug) answered ($status)" }
              }
            }

            ^${waitForMcpProxy}
            refresh $api $headers
            sleep 11min
            refresh $api $headers
          '';
      };

      # The PGlite executor itself runs, so dumps and restores read and write
      # exactly its on-disk format.
      pglite = "${pkgs.pkgs-mine.executor}/lib/executor/runtime/node_modules/@electric-sql/pglite";

      # Every table except the derived executor_tool_search* index, as
      # <schema>.<table>.csv sorted by the first column.
      dumpTables =
        pkgs.writeText "executor-dump-tables.mjs" # javascript
          ''
            import { mkdir, writeFile } from 'node:fs/promises';
            const [pglite, dir, out] = process.argv.slice(2);
            const { PGlite } = await import(`''${pglite}/dist/index.js`);
            const db = await PGlite.create(dir);
            const tables = (await db.query(`select schemaname, tablename from pg_tables
              where schemaname not in ('pg_catalog', 'information_schema')
                and tablename not like 'executor_tool_search%' order by 1, 2`)).rows;
            await mkdir(out, { recursive: true });
            for (const { schemaname, tablename } of tables) {
              const ident = `"''${schemaname}"."''${tablename}"`;
              const result = await db.query(
                `copy (select * from ''${ident} order by 1) to '/dev/blob' with (format csv, header)`,
              );
              await writeFile(`''${out}/''${schemaname}.''${tablename}.csv`, Buffer.from(await result.blob.arrayBuffer()));
            }
            await db.close();
          '';

      # Loads a dump into a freshly created database of the same schema
      # version. The private_* bookkeeping tables stay as the fresh start wrote
      # them; everything else is replaced in one transaction.
      restoreTables =
        pkgs.writeText "executor-restore-tables.mjs" # javascript
          ''
            import { readdir, readFile } from 'node:fs/promises';
            const [pglite, dir, dump] = process.argv.slice(2);
            const { PGlite } = await import(`''${pglite}/dist/index.js`);
            const db = await PGlite.create(dir);
            const files = (await readdir(dump)).filter((f) => f.endsWith('.csv'));
            const settings = files.find((f) => f.endsWith('.private_executor_settings.csv'));
            if (settings) {
              const dumped = (await readFile(`''${dump}/''${settings}`, 'utf8')).match(/^version,(.*)$/m)?.[1];
              const fresh = (await db.query(`select value from private_executor_settings where key = 'version'`)).rows[0]?.value;
              if (dumped !== fresh) throw new Error(`schema version mismatch: dump ''${dumped}, database ''${fresh}`);
            }
            const tables = files
              .map((f) => [f, f.slice(0, -4).split('.')])
              .filter(([, [, table]]) => !table.startsWith('private_'))
              .map(([f, [schema, table]]) => [f, `"''${schema}"."''${table}"`]);
            await db.transaction(async (tx) => {
              await tx.exec('set local session_replication_role = replica');
              // One statement, so tables that reference each other truncate together.
              await tx.exec(`truncate ''${tables.map(([, ident]) => ident).join(', ')}`);
              for (const [f, ident] of tables) {
                const blob = new Blob([await readFile(`''${dump}/''${f}`)]);
                await tx.query(`copy ''${ident} from '/dev/blob' with (format csv, header)`, [], { blob });
              }
            });
            await db.close();
            console.log(`restored ''${tables.length} tables into ''${dir}`);
          '';

      restoreState = pkgs.writeShellApplication {
        name = "executor-restore-state";
        runtimeInputs = [
          pkgs.nodejs
          pkgs.systemd
        ];
        text = # sh
          ''
            if [ "$#" -ne 2 ]; then
              echo "usage: executor-restore-state <unpacked backup dir> <data dir>" >&2
              exit 2
            fi
            if systemctl is-active --quiet executor-web; then
              echo "stop executor-web first" >&2
              exit 1
            fi
            for db in executor mcp-auth; do
              [ -d "$1/$db" ] || continue
              node ${restoreTables} ${pglite} "$2/$db.pglite" "$1/$db"
            done
          '';
      };

      # v2 persists state as PGlite directories plus installation.json under
      # EXECUTOR_DATA_DIR (apps/local/server/README.md). The backup keeps the
      # rows of executor.pglite and mcp-auth.pglite (MCP OAuth clients and
      # tokens) as CSV, one file per table, plus installation.json,
      # repositories/ (app sources) and builds/ (deployments point at these
      # blobs and fail with RuntimeBuildUnavailable without them). Left out:
      # the executor_tool_search* tables, derived data rebuilt on the next
      # search or executor-refresh-tools (vectors refill from the local embed
      # server); browser-auth.pglite (web UI sessions; losing it means logging
      # in again); diagnostics/ and workerd/. A raw copy of the PGlite dirs
      # was ~200 MB, nearly all search index and WAL, for ~0.2 MB of rows.
      # The API key and encryption key are NOT backed up here: they live in
      # secrets/executor-v2.yaml already, supplied at start instead of a
      # keys.json/OS-keyring record (see the docs' "Back up and update").
      #
      # Restore (executor-restore-state, tested against a fresh install):
      # decrypt and unpack the tarball; stop executor-web; start the same
      # executor version once on an empty EXECUTOR_DATA_DIR with the same keys
      # so it creates the schema, then stop it; run executor-restore-state
      # <unpacked dir> <data dir>, which checks the schema version matches and
      # loads every non-bookkeeping table; copy installation.json,
      # repositories/ and builds/ back; start executor-web and run
      # executor-refresh-tools.
      #
      # modules/nixos/hardware-configuration.nix mounts /home as its own
      # btrfs subvolume (@home), with @snapshots reserved at /.snapshots for
      # exactly this: a read-only `btrfs subvolume snapshot` is atomic and
      # crash-consistent (equivalent to a power-cut view of the filesystem),
      # which PGlite (like any WAL-based Postgres) tolerates — unlike a plain
      # live `cp`/`tar`, which can catch a file mid-write. Tar the data dir
      # out of the snapshot, then drop the snapshot immediately.
      #
      # This needs root (btrfs subvolume administration is not grantable to
      # a normal user without a setuid helper), so the unit runs as root and
      # chowns the file it writes back to the user before exiting. If /home
      # is ever not a btrfs subvolume (a different host, a reinstall that
      # changes the layout), this falls back to tarring the live directory
      # directly — a best-effort snapshot, not a guaranteed-consistent one.
      backupState = pkgs.writeShellApplication {
        name = "executor-backup";
        runtimeInputs = [
          pkgs.btrfs-progs
          pkgs.coreutils
          pkgs.gnutar
          pkgs.nodejs
          pkgs.sops
          pkgs.zstd
        ];
        text = # sh
          ''
            repo=${userHome}/Projects/dots
            stamp=${userHome}/.local/state/executor-v2-backup.sha256
            [ -d "$repo/secrets" ] || exit 0
            [ -e ${dataDir}/executor.pglite ] || exit 0

            snapshot=/.snapshots/executor-backup
            tmp=""
            # A snapshot is a subvolume: rm -rf can't remove it (read-only) and
            # walks all of /home trying. Always delete it as a subvolume.
            drop_snapshot() {
              if [ -e "$snapshot" ]; then btrfs subvolume delete "$snapshot" >/dev/null; fi
            }
            drop_snapshot
            tarsrc=${dataDir}
            cleanup() { drop_snapshot || true; if [ -n "$tmp" ]; then rm -rf "$tmp"; fi; }
            if btrfs subvolume snapshot -r /home "$snapshot" >/dev/null 2>&1; then
              tarsrc="$snapshot/${dataDirRelativeToHome}"
            else
              echo "warning: /home is not a btrfs subvolume; backing up the live data dir without a snapshot" >&2
            fi
            trap cleanup EXIT

            tmp=$(mktemp -d)
            # PGlite has to write to open a database, so dump from copies.
            mkdir "$tmp/db" "$tmp/state"
            for db in executor mcp-auth; do
              [ -e "$tarsrc/$db.pglite" ] || continue
              cp -a "$tarsrc/$db.pglite" "$tmp/db/"
              rm -f "$tmp/db/$db.pglite/postmaster.pid"
              node ${dumpTables} ${pglite} "$tmp/db/$db.pglite" "$tmp/state/$db"
            done
            cp -a "$tarsrc/installation.json" "$tarsrc/repositories" "$tarsrc/builds" "$tmp/state/"
            drop_snapshot
            # Reproducible, so unchanged state hashes the same and is skipped.
            tar -C "$tmp/state" --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cf - . \
              | zstd -q -19 -T0 > "$tmp/state.tar.zst"

            sum=$(sha256sum "$tmp/state.tar.zst" | cut -d' ' -f1)
            [ "$sum" = "$(cat "$stamp" 2>/dev/null || true)" ] && exit 0
            cd "$repo"
            sops -e --input-type binary --output-type json --filename-override secrets/executor.json "$tmp/state.tar.zst" > "$tmp/executor.json"
            mv "$tmp/executor.json" secrets/executor.json
            chown ${defaultUser}:users secrets/executor.json
            mkdir -p "$(dirname "$stamp")"
            echo "$sum" > "$stamp"
            chown ${defaultUser}:users "$stamp"
            echo "wrote $repo/secrets/executor.json"
          '';
      };

      # The daemon wants EXECUTOR_API_KEY as an env var, not a file, and the
      # value clients already send (EXECUTOR_AUTH_TOKEN) lives in the sops
      # shell-env blob, decrypted by sops-nix to /run/secrets/shell-env at
      # runtime (modules/_lib/sops-common.nix) — not addressable per key at
      # build time (secrets/executor-v2.yaml held its own freshly generated
      # api_key before this; dropped now that nothing needs rotating).
      # Parse the one line we need instead of sourcing the whole file, so
      # arbitrary content in it never runs as shell.
      executorStart = pkgs.writeShellApplication {
        name = "executor-web-start";
        runtimeInputs = [ pkgs.gnused ];
        text = # sh
          ''
            if [ ! -r /run/secrets/shell-env ]; then
              echo "executor-web: /run/secrets/shell-env is missing or unreadable" >&2
              exit 1
            fi
            token=$(sed -n 's/^EXECUTOR_AUTH_TOKEN=//p' /run/secrets/shell-env)
            if [ -z "$token" ]; then
              echo "executor-web: EXECUTOR_AUTH_TOKEN missing from /run/secrets/shell-env" >&2
              exit 1
            fi
            if [ "''${#token}" -lt 32 ]; then
              echo "executor-web: EXECUTOR_AUTH_TOKEN is shorter than 32 characters" >&2
              exit 1
            fi
            export EXECUTOR_API_KEY="$token"
            exec ${pkgs.pkgs-mine.executor}/bin/executor serve
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

        environment.systemPackages = [ restoreState ];

        # Create workspace directory
        systemd.tmpfiles.rules = [
          "d ${executorWorkspace} 0755 ${defaultUser} users - -"
        ];

        # secrets/executor-v2.yaml is its own sops file (not nested in
        # secrets/main.yaml), so the secret names are flat, matching that
        # file's top-level keys.
        sops.secrets = {
          "executor-v2-encryption-key" = {
            sopsFile = ../../secrets/executor-v2.yaml;
            key = "encryption_key";
          };
        };

        # EXECUTOR_ENCRYPTION_KEY, supplied from sops instead of letting the
        # daemon write keys.json or an OS-keyring record. Must be kept for
        # every start (cli.mdx, "Configure it"). EXECUTOR_API_KEY is NOT
        # templated here: executorStart below derives it at start from the
        # same EXECUTOR_AUTH_TOKEN the MCP clients already send, so nothing
        # needs rotating in the clients.
        sops.templates."executor-v2.env" = {
          owner = defaultUser;
          content = ''
            EXECUTOR_ENCRYPTION_KEY=${config.sops.placeholder."executor-v2-encryption-key"}
          '';
          restartUnits = [ "executor-web.service" ];
        };

        # Main executor web service
        systemd.services.executor-web = {
          description = "Executor web server";
          after = [
            "network.target"
            "podman-mcp.service"
            # executorStart reads /run/secrets/shell-env at start.
            "sops-install-secrets.service"
          ];
          wantedBy = [ "multi-user.target" ];
          # Intentionally no `partOf`/`bindsTo` on podman-mcp: with stateless
          # streamable HTTP, proxy restarts are transparent. Cascading a restart
          # here would re-run config-sync before the new proxy is listening,
          # leaving sources with empty tool manifests until a manual re-probe.

          environment = {
            HOME = userHome;
            EXECUTOR_DATA_DIR = dataDir;
            EXECUTOR_PORT = toString cfg.port;
            # v2 binds only 127.0.0.1 and has no --allowed-host; this is what
            # it bakes into generated dashboard/pairing links instead.
            EXECUTOR_BROWSER_ORIGIN = "https://${cfg.subdomain}.${config.services.local-networking.baseDomain}";
            # Startup fails at "composition" without a CA bundle; systemd units
            # don't inherit the login shell's SSL_CERT_FILE.
            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
            EXECUTOR_NO_UPDATE_CHECK = "1";
            EXECUTOR_DISABLE_ANALYTICS = "1";
            # Search -> tool-call events for search evals (~/Projects/snippet-evals/usage.py).
            # Implemented by the v2-search patches (packages/executor/default.nix, patches = []).
            EXECUTOR_USAGE_LOG = "${executorWorkspace}/usage.jsonl";
            # Local embedding server for hybrid tools.search; keyword-only when down.
            EXECUTOR_EMBED_URL = "http://127.0.0.1:38978/v1/embeddings";
            # Dashboards re-mount other apps' tools, and the built-in executor app is
            # management only; both stay reachable with an explicit namespace.
            EXECUTOR_SEARCH_EXCLUDE_APPS = "executor,tickets,delivery,agenda,inbox,slack-triage,scribe-meetings";
          };

          serviceConfig = {
            User = defaultUser;
            WorkingDirectory = executorWorkspace;
            EnvironmentFile = config.sops.templates."executor-v2.env".path;
            # Gate the daemon on the proxy being reachable (see waitForMcpProxy).
            ExecStartPre = [ waitForMcpProxy ];
            ExecStart = lib.getExe executorStart;
            Restart = "on-failure";
            RestartSec = 5;
            StandardOutput = "journal";
            StandardError = "journal";
            SyslogIdentifier = "executor-web";
          };
        };

        # wantedBy starts it with podman-mcp; partOf restarts it when podman-mcp
        # restarts mid-run, so every proxy start gets both passes.
        systemd.services.executor-refresh-tools = {
          description = "Refresh Executor's tool search after mcp-proxy starts";
          after = [
            "executor-web.service"
            "podman-mcp.service"
          ];
          partOf = [ "podman-mcp.service" ];
          wantedBy = [ "podman-mcp.service" ];
          serviceConfig = {
            Type = "simple";
            User = defaultUser;
            ExecStart = lib.getExe refreshToolIndex;
          };
        };

        systemd.services.executor-backup = {
          description = "Back up executor v2 state into the dots repo";
          after = [ "executor-web.service" ];
          serviceConfig = {
            Type = "oneshot";
            # Root: btrfs subvolume snapshot/delete has no normal-user grant
            # short of a setuid helper. backupState chowns what it writes in
            # the user's repo back to defaultUser before exiting.
            User = "root";
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
