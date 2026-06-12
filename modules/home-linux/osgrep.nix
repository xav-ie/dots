{
  flake.modules.homeManager.linux =
    {
      config,
      pkgs,
      ...
    }:
    let
      homeDir = config.home.homeDirectory;
      realOsgrep = "${homeDir}/.npm/bin/osgrep";

      # osgrep unconditionally appends `.osgrep` to a repo's TRACKED .gitignore
      # on every command (index, search, the plugin's auto `serve`) — see
      # ensureGitignoreEntry in dist/lib/utils/project-root.js. It has no flag,
      # env var, or escape hatch to disable this. So we neuter it at the syscall
      # boundary: a Node preload (NODE_OPTIONS=--require) that makes any write to
      # a file named `.gitignore` a silent no-op. osgrep thinks it succeeded;
      # the file is never touched. The in-tree `.osgrep/` index dir itself is
      # kept out of `git status` by the global core.excludesFile entry
      # (`.osgrep` in modules/home/git.nix), so no per-repo files are touched at
      # all. The CJS bundle reaches fs via a live-binding getter, so patching the
      # required `fs` object propagates into osgrep's call.
      gitignoreGuard = pkgs.writeText "osgrep-no-gitignore.cjs" ''
        "use strict";
        const path = require("node:path");
        function isGitignore(p) {
          try {
            const s =
              typeof p === "string"
                ? p
                : p && typeof p.toString === "function"
                  ? p.toString()
                  : "";
            return path.basename(s) === ".gitignore";
          } catch (_e) {
            return false;
          }
        }
        const fs = require("node:fs");
        for (const name of ["writeFileSync", "appendFileSync"]) {
          const orig = fs[name];
          if (typeof orig !== "function") continue;
          fs[name] = function (file) {
            if (isGitignore(file)) return undefined;
            return orig.apply(this, arguments);
          };
        }
        for (const name of ["writeFile", "appendFile"]) {
          const orig = fs[name];
          if (typeof orig !== "function") continue;
          fs[name] = function (file) {
            if (isGitignore(file)) {
              const cb = arguments[arguments.length - 1];
              if (typeof cb === "function") return cb(null);
              return undefined;
            }
            return orig.apply(this, arguments);
          };
        }
        try {
          const fsp = require("node:fs/promises");
          for (const name of ["writeFile", "appendFile"]) {
            const orig = fsp[name];
            if (typeof orig !== "function") continue;
            fsp[name] = function (file) {
              if (isGitignore(file)) return Promise.resolve();
              return orig.apply(this, arguments);
            };
          }
        } catch (_e) {}
      '';

      # Front osgrep with the preload so EVERY entry point is covered — the
      # plugin spawns `osgrep` via PATH, and ~/.local/bin sorts before
      # ~/.npm/bin, so this wrapper wins.
      osgrep-wrapper = pkgs.writeShellApplication {
        name = "osgrep";
        text = ''
          export NODE_OPTIONS="--require ${gitignoreGuard}''${NODE_OPTIONS:+ ''${NODE_OPTIONS}}"
          exec ${realOsgrep} "$@"
        '';
      };

      # The indexing allowlist is PRIVATE (it names work projects), so it is read
      # at runtime from the SAME opaque sops blob mgrep uses — {folders, ...}.
      # osgrep only needs `folders`; the rest is mgrep-only and ignored here.
      configPath = "/run/secrets/mgrep/config";

      # Patterns osgrep's built-in defaults DON'T cover but should never be
      # indexed in any repo. Minified bundles are single-line, so osgrep chunks
      # them into enormous counts → slow embeds + bloated indexes for zero
      # search value; generated .d.ts are noise (the .ts source is indexed).
      # Written to every repo's .osgrepignore ahead of the per-repo extraIgnore.
      baseIgnore = ''
        *.min.js
        *.min.mjs
        *.min.css
        *.d.ts
        .devenv
        .direnv
      '';
      baseIgnoreFile = pkgs.writeText "osgrep-baseignore" baseIgnore;

      # Periodic background index of the allowlist. The per-session `osgrep
      # serve` daemon (started by the Claude Code plugin) live-watches repos
      # you're actively in; this covers the rest. `index` takes a writer lock
      # (serializes safely against a running `serve`) and prunes files now gone
      # or ignored on every run, so no separate reconcile is needed. We cd into
      # each repo and run the WRAPPER so the .gitignore guard is in effect.
      # Failures are logged, not fatal — one bad repo never blocks the rest.
      osgrep-index = pkgs.writeShellApplication {
        name = "osgrep-index";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.gnused
          pkgs.jq
        ];
        text = # sh
          ''
            config="''${OSGREP_INDEX_CONFIG:-${configPath}}"
            if [ ! -r "$config" ]; then
              echo "osgrep config not readable: $config" >&2
              exit 1
            fi

            mapfile -t folders < <(jq -r '.folders[]' "$config")
            n=0
            total=''${#folders[@]}
            for d in "''${folders[@]}"; do
              n=$((n + 1))
              if [ ! -d "$d" ]; then
                echo "[$n/$total] skip (missing): $d"
                continue
              fi
              cd "$d" || {
                echo "[$n/$total] FAILED (cd): $d"
                continue
              }
              # osgrep only honors .gitignore + .osgrepignore — NOT git's global
              # excludesFile or .git/info/exclude. So write .osgrepignore =
              # baseIgnore (minified/generated noise its defaults miss) + the
              # per-repo extraIgnore from the sops map (which hides vendored
              # subtrees git keeps in .git/info/exclude, e.g. quicksilver's
              # comfrt/ Shopify theme — without it osgrep walks 1700+ files into
              # a 275MB index and a 20min hang). .osgrepignore is globally
              # git-ignored, so it's invisible.
              extra="$(jq -r --arg k "$(basename "$d")" '.extraIgnore[$k] // ""' "$config")"
              {
                cat ${baseIgnoreFile}
                printf '%s\n' "$extra"
              } > .osgrepignore
              start=$SECONDS
              # Per-repo summary only (no per-file output). osgrep's non-verbose
              # "Indexing complete(P / T) • indexed N" line gives files-seen and
              # files-(re)embedded. `if out=$(...)` (not a bare assignment) keeps
              # set -e from aborting the whole pass on one failing/timed-out repo,
              # and captures rc.
              if out=$(timeout 1200 ${osgrep-wrapper}/bin/osgrep index 2>&1); then
                rc=0
              else
                rc=$?
              fi
              elapsed=$((SECONDS - start))
              if [ "$rc" -eq 0 ]; then
                complete=$(printf '%s\n' "$out" | grep -a 'Indexing complete' | tail -1)
                files=$(printf '%s' "$complete" | sed -nE 's/.*complete\([0-9]+[^0-9]+([0-9]+)\).*/\1/p')
                embedded=$(printf '%s' "$complete" | sed -nE 's/.*indexed ([0-9]+).*/\1/p')
                echo "[$n/$total] ok: $d (''${files:-?} files, ''${embedded:-0} embedded, ''${elapsed}s)"
              else
                echo "[$n/$total] FAILED ($rc): $d (''${elapsed}s)"
              fi
            done
          '';
      };
    in
    {
      config = {
        # Shadow ~/.npm/bin/osgrep (later on PATH) with the guarded wrapper.
        home.file.".local/bin/osgrep".source = "${osgrep-wrapper}/bin/osgrep";

        # ExecStart below points at this stable symlink rather than the
        # `${osgrep-index}` store path. The store path changes whenever the
        # indexer script or the .gitignore guard changes, which rewrites the
        # unit file — and home-manager then *restarts this oneshot
        # synchronously* during `reloadSystemd`. A full re-index runs ~15min,
        # so that blocks activation past its timeout (it took down a switch).
        # A fixed ExecStart keeps the unit text invariant: the symlink
        # retargets without a unit change, and the next timer run picks up the
        # new script. So home-manager never waits on the long index.
        home.file.".local/bin/osgrep-index".source = "${osgrep-index}/bin/osgrep-index";

        systemd.user.services.osgrep-index = {
          Unit.Description = "Index allowlisted repos into their local osgrep store";
          Service = {
            Type = "oneshot";
            # Background pass: stay out of the way of interactive work. osgrep's
            # defaults are greedy (4 worker threads, per-worker memory cap = 50%
            # of system RAM — a partial pass already peaked at 4.6 GB), so cap
            # both and run at low CPU/IO priority. These apply ONLY to the timer
            # service; interactive `osgrep` via the wrapper keeps full speed.
            Environment = [
              "OSGREP_WORKER_THREADS=4"
              "OSGREP_MAX_WORKER_MEMORY_MB=2048"
            ];
            Nice = 15;
            IOSchedulingClass = "idle";
            ExecStart = "${homeDir}/.local/bin/osgrep-index";
          };
        };

        systemd.user.timers.osgrep-index = {
          Unit.Description = "Periodic osgrep index (30 min after each run)";
          Timer = {
            # OnActiveSec bootstraps a run shortly after the timer STARTS — which
            # happens on every boot AND every rebuild — so it always self-starts
            # (OnBootSec is relative to boot, so it's already elapsed on a no-
            # reboot rebuild and never fires). OnUnitInactiveSec (NOT
            # OnUnitActiveSec) then re-arms 30 min after each run FINISHES; for a
            # long oneshot, OnUnitActiveSec anchors to activation and leaves
            # NextElapse=infinity once it goes inactive, so it silently dies.
            OnActiveSec = "5m";
            OnUnitInactiveSec = "30m";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      };
    };
}
