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

      # osgrep indexes only a hard-coded extension set, which lacks Nix and
      # Nushell. Files without a tree-sitter grammar get line-window chunks
      # (like .sh), so adding the extensions to the exported Set is enough.
      extraExtensions = pkgs.writeText "osgrep-extra-extensions.cjs" ''
        "use strict";
        const Module = require("node:module");
        const load = Module._load;
        Module._load = function () {
          const m = load.apply(this, arguments);
          if (m && m.INDEXABLE_EXTENSIONS instanceof Set) {
            m.INDEXABLE_EXTENSIONS.add(".nix");
            m.INDEXABLE_EXTENSIONS.add(".nu");
          }
          return m;
        };
      '';

      # Front osgrep with the preloads so EVERY entry point is covered —
      # ~/.local/bin sorts before ~/.npm/bin, so this wrapper wins.
      #
      # Worktrees of a bare repo share one index: its <default branch>
      # worktree, kept current by osgrep-index. `search` from any other
      # worktree runs there from the same subdirectory, so result paths stay
      # valid here (hits reflect the default branch, not this one's changes)
      # instead of indexing every worktree separately. Repos without an index
      # are refused rather than indexed on the spot.
      osgrep-wrapper = pkgs.writeShellApplication {
        name = "osgrep";
        # Required: ~/.npm/bin/osgrep has a `#!/usr/bin/env node` shebang and
        # writeShellApplication's PATH holds only runtimeInputs. nodejs_24
        # matches programs.npm.package, the runtime it was installed with.
        runtimeInputs = [
          pkgs.coreutils
          pkgs.git
          pkgs.nodejs_24
        ];
        text = ''
          export NODE_OPTIONS="--require ${gitignoreGuard} --require ${extraExtensions}''${NODE_OPTIONS:+ ''${NODE_OPTIONS}}"
          if [ "''${1:-}" = search ] && top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
            common="$(git rev-parse --path-format=absolute --git-common-dir)"
            if [ "$(git --git-dir="$common" rev-parse --is-bare-repository)" = true ] &&
              head="$(git --git-dir="$common" symbolic-ref --quiet --short refs/remotes/origin/HEAD)"; then
              index="$(dirname "$common")/''${head#origin/}"
              if [ "$top" != "$index" ] && [ -d "$index/.osgrep" ]; then
                echo "osgrep: searching the ''${head#origin/} index" >&2
                cd "$index''${PWD#"$top"}" 2>/dev/null || cd "$index"
              fi
            fi
            # Only the indexer creates indexes; a search elsewhere would
            # silently index the whole repo.
            if [ ! -d "$(git rev-parse --show-toplevel)/.osgrep" ]; then
              echo "osgrep: no index for this repo (not in the allowlist); use grep" >&2
              exit 2
            fi
          fi
          exec ${realOsgrep} "$@"
        '';
      };

      # The indexing allowlist is PRIVATE (it names work projects), so it is read
      # at runtime from the SAME opaque sops blob mgrep uses — {folders, ...}.
      # osgrep only needs `folders`; the rest is mgrep-only and ignored here.
      configPath = "/run/secrets/osgrep/config";

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

      # Periodic background index of the allowlist. An allowlisted bare repo's
      # directory holds all its worktrees, so only its <default branch>
      # worktree is indexed. `index` takes a writer lock
      # (serializes safely against a running `serve`) and prunes files now gone
      # or ignored on every run, so no separate reconcile is needed. We cd into
      # each repo and run the WRAPPER so the .gitignore guard is in effect.
      # Failures are logged, not fatal — one bad repo never blocks the rest.
      osgrep-index = pkgs.writeShellApplication {
        name = "osgrep-index";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.gawk
          pkgs.git
          pkgs.gnugrep
          pkgs.gnused
          pkgs.jq
          pkgs.openssh
        ];
        text = # sh
          ''
            config="''${OSGREP_INDEX_CONFIG:-${configPath}}"
            if [ ! -r "$config" ]; then
              echo "osgrep config not readable: $config" >&2
              exit 1
            fi
            # Fail instead of prompting when the SSH key is locked.
            export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15"
            export GIT_TERMINAL_PROMPT=0

            is_bare() {
              [ "$(git -C "$1" rev-parse --is-bare-repository 2>/dev/null)" = true ]
            }
            # An allowlisted bare repo's directory holds all its worktrees, so
            # it is indexed through one <default branch> worktree instead:
            # fetched at most daily (refreshing origin/HEAD, which git only
            # sets at clone time), then created or moved to origin's tip on
            # every run. Dirty or diverged worktrees are left as they are.
            upstream() {
              local d="$1" common head def wt
              common="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir)"
              if [ -z "$(find "$common/FETCH_HEAD" -mmin -1440 2>/dev/null)" ]; then
                timeout 180 git -C "$d" fetch --quiet --prune origin || echo "fetch failed: $d" >&2
                timeout 60 git -C "$d" remote set-head origin --auto >/dev/null 2>&1 || true
              fi
              head="$(git -C "$d" symbolic-ref --quiet --short refs/remotes/origin/HEAD)" || return 0
              def="''${head#origin/}"
              wt="$d/$def"
              if [ ! -e "$wt" ]; then
                git -C "$d" -c core.hooksPath=/dev/null worktree add --quiet --detach "$wt" "$head" >&2 || return 0
              elif [ -z "$(git -C "$wt" status --porcelain --untracked-files=no)" ]; then
                case "$(git -C "$wt" branch --show-current)" in
                  "") git -C "$wt" -c core.hooksPath=/dev/null checkout --quiet --detach "$head" >&2 || true ;;
                  "$def") git -C "$wt" merge --quiet --ff-only "$head" >&2 || true ;;
                esac
              fi
              echo "$wt"
            }
            resolve() {
              if is_bare "$1"; then upstream "$1"; else echo "$1"; fi
            }
            mapfile -t folders < <(
              jq -r '.folders[]' "$config" | while read -r d; do resolve "$d"; done | awk '!seen[$0]++'
            )
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
              key="$(basename "$d")"
              if is_bare "$(dirname "$d")"; then key="$(basename "$(dirname "$d")")"; fi
              extra="$(jq -r --arg k "$key" '.extraIgnore[$k] // ""' "$config")"
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
