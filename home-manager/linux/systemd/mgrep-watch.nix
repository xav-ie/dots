{
  config,
  pkgs,
  ...
}:
let
  homeDir = config.home.homeDirectory;
  mgrep = "${homeDir}/.npm/bin/mgrep";

  # The indexing allowlist (folders), index worktrees, and per-repo extra
  # ignores are PRIVATE (they name work projects), so they live in sops and are
  # read at runtime — not baked into the Nix store. Decrypts to this path; set
  # $MGREP_CONFIG to override. Schema:
  #   { "folders": ["/home/x/Work/foo", ...],
  #     "worktrees": ["/home/x/Work/bar|main", ...],
  #     "extraIgnore": { "<repo basename>": "<.mgrepignore additions>" } }
  configPath = "/run/secrets/mgrep/config";

  # Base ignore rules applied to every watched repo via a generated
  # .mgrepignore. mgrep's sync only reads literal .gitignore/.mgrepignore
  # files — it does NOT honor git's global excludesFile or .git/info/exclude —
  # so transient and build artifacts must be listed here explicitly. This is
  # generic (no private names), so it stays in the store.
  baseIgnore = ''
    # Atomic-write temp files (e.g. index.ts.tmp.<pid>.<hash>).
    *.tmp
    *.tmp.*

    # Build output
    dist/
    build/
    out/
    .next/
    .turbo/
    coverage/

    # Dependencies — never index
    node_modules/

    # Lockfiles (mgrep's defaults already cover *.lock, e.g. yarn.lock).
    package-lock.json
    npm-shrinkwrap.json
    pnpm-lock.yaml
    bun.lockb

    # Nix build outputs (symlinks into /nix/store), at repo root.
    /result
    /result-*

    # Generated type declarations (search .ts source, not these).
    *.d.ts
    graphql-types/

    # Sourcemaps, build caches, test reports.
    *.map
    local-cache.json
    playwright-report/
    vfs.js
    vfs-images.js

    # Media / binary / fonts (not meaningfully searchable).
    *.png
    *.jpg
    *.jpeg
    *.gif
    *.webp
    *.avif
    *.ico
    *.svg
    *.woff
    *.woff2
    *.ttf
    *.eot
    *.otf

    # Minified bundles (re-included per-repo via extraIgnore where they are the
    # RE target).
    *.min.js
    *.min.mjs
    *.min.css
  '';
  baseIgnoreFile = pkgs.writeText "mgrep-baseignore" baseIgnore;

  # Periodic sync instead of `mgrep watch`: the live watcher recursively
  # inotify-watches the whole tree (including node_modules), exhausting
  # fs.inotify.max_user_watches across many repos. `mgrep search --sync` runs
  # the same reconciling sync (upload changed, prune removed/ignored) with
  # zero inotify watches, then exits. Failures are logged, not fatal, so one
  # bad repo never blocks the rest. The per-repo .mgrepignore is (re)written
  # here from the baked baseIgnore plus the repo's private extraIgnore.
  mgrep-sync = pkgs.writeShellApplication {
    name = "mgrep-sync";
    runtimeInputs = [
      pkgs.nodejs
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      config="''${MGREP_CONFIG:-${configPath}}"
      if [ ! -r "$config" ]; then
        echo "mgrep config not readable: $config" >&2
        exit 1
      fi

      mapfile -t folders < <(jq -r '.folders[]' "$config")
      for d in "''${folders[@]}"; do
        [ -d "$d" ] || {
          echo "skip (missing): $d"
          continue
        }
        extra="$(jq -r --arg k "$(basename "$d")" '.extraIgnore[$k] // ""' "$config")"
        {
          cat ${baseIgnoreFile}
          printf '%s\n' "$extra"
        } > "$d/.mgrepignore"
        if (cd "$d" && timeout 300 ${mgrep} search --sync --max-file-count 5000 --no-rerank -m 1 "sync" . >/dev/null 2>&1); then
          echo "ok: $d"
        else
          echo "FAILED ($?): $d"
        fi
      done
    '';
  };

  # Fast-forward each index worktree to origin/<branch>. ff-only so a dirty
  # or diverged worktree is skipped, never clobbered. Auth uses the
  # passphrase-less id_ed25519 directly, so no ssh-agent is required. Each
  # worktree entry is "<worktree path>|<branch>", read from the sops config.
  mgrep-worktree-pull = pkgs.writeShellApplication {
    name = "mgrep-worktree-pull";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      config="''${MGREP_CONFIG:-${configPath}}"
      if [ ! -r "$config" ]; then
        echo "mgrep config not readable: $config" >&2
        exit 1
      fi

      export GIT_SSH_COMMAND="ssh -i ${homeDir}/.ssh/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
      export GIT_TERMINAL_PROMPT=0
      mapfile -t worktrees < <(jq -r '.worktrees[]' "$config")
      for entry in "''${worktrees[@]}"; do
        d="''${entry%%|*}"
        b="''${entry##*|}"
        [ -d "$d" ] || {
          echo "skip (missing): $d"
          continue
        }
        cur="$(git -C "$d" rev-parse --abbrev-ref HEAD)"
        if [ "$cur" != "$b" ]; then
          echo "skip ($d on '$cur', expected '$b')"
          continue
        fi
        if timeout 120 git -C "$d" fetch --quiet origin "$b" \
          && git -C "$d" merge --ff-only --quiet "origin/$b"; then
          echo "ok: $d -> $(git -C "$d" rev-parse --short HEAD)"
        else
          echo "FAILED (no ff): $d"
        fi
      done
    '';
  };
in
{
  config = {
    systemd.user.services.mgrep-worktree-pull = {
      Unit.Description = "Fast-forward mgrep index worktrees to upstream";
      Service = {
        Type = "oneshot";
        ExecStart = "${mgrep-worktree-pull}/bin/mgrep-worktree-pull";
      };
    };

    systemd.user.services.mgrep-sync = {
      Unit = {
        Description = "Sync allowlisted repos into the mgrep store";
        # Pull mainline worktrees first so their updates are indexed this run.
        Wants = [ "mgrep-worktree-pull.service" ];
        After = [ "mgrep-worktree-pull.service" ];
      };
      Service = {
        Type = "oneshot";
        # Optional: put MXBAI_API_KEY=... here for non-expiring auth that
        # survives token expiry. Falls back to the browser login token.
        EnvironmentFile = [ "-${homeDir}/.config/mgrep/watch.env" ];
        ExecStart = "${mgrep-sync}/bin/mgrep-sync";
      };
    };

    systemd.user.timers.mgrep-sync = {
      Unit.Description = "Periodic mgrep store sync (every 30 min)";
      Timer = {
        OnBootSec = "3m";
        OnUnitActiveSec = "30m";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };

    # Weekly reconcile: mgrep's `--sync` adds files but never removes them (its
    # delete uses the path, the API needs the UUID id), so deleted/renamed
    # source files would linger. This deletes-by-id everything now ignored,
    # gone from disk, or orphaned.
    systemd.user.services.mgrep-reconcile = {
      Unit.Description = "Reconcile mgrep store (remove stale/ignored/orphaned files)";
      Service = {
        Type = "oneshot";
        EnvironmentFile = [ "-${homeDir}/.config/mgrep/watch.env" ];
        ExecStart = "${pkgs.nodejs}/bin/node ${./mgrep-reconcile.mjs}";
      };
    };

    systemd.user.timers.mgrep-reconcile = {
      Unit.Description = "Weekly mgrep store reconcile";
      Timer = {
        OnCalendar = "Sun 04:00";
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
