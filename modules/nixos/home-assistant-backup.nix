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
      userHome = "/home/${defaultUser}";

      # Home Assistant's UI-managed config, the ZHA database and the Matter
      # server's fabric, as one sops leaf per file in secrets/hass-state.json.
      # Keys are paths relative to /var/lib; files that aren't UTF-8 are
      # stored base64 under "<path>.base64". Left out: the recorder history
      # database, logs, and state that only caches or traces
      # (core.restore_state, trace.saved_traces, bluetooth.*).
      #
      # Restore: sudo hass-unpack-state <repo> <dir>; stop home-assistant and
      # matterjs-server; copy <dir>/hass into /var/lib/hass (chown hass:hass)
      # and <dir>/private/matterjs-server into /var/lib/private/matterjs-server;
      # start both.
      unpackState = pkgs.writeShellApplication {
        name = "hass-unpack-state";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          pkgs.sops
        ];
        text = # sh
          ''
            if [ "$#" -ne 2 ]; then
              echo "usage: hass-unpack-state <repo dir> <output dir>" >&2
              exit 2
            fi
            out=$2
            tmp=$(mktemp -d)
            trap 'rm -rf "$tmp"' EXIT
            sops -d "$1/secrets/hass-state.json" > "$tmp/state.json"
            jq -r 'keys[]' "$tmp/state.json" | while IFS= read -r k; do
              case $k in
                *.base64) f=$out/''${k%.base64} ;;
                *) f=$out/$k ;;
              esac
              mkdir -p "$(dirname "$f")"
              case $k in
                *.base64) jq -j --arg k "$k" '.[$k]' "$tmp/state.json" | base64 -d > "$f" ;;
                *) jq -j --arg k "$k" '.[$k]' "$tmp/state.json" > "$f" ;;
              esac
            done
          '';
      };

      # /var is its own btrfs subvolume (@var), so a read-only snapshot gives
      # a crash-consistent view of the SQLite and JSON stores while both
      # services keep running.
      backupState = pkgs.writeShellApplication {
        name = "hass-backup";
        runtimeInputs = [
          pkgs.btrfs-progs
          pkgs.coreutils
          pkgs.findutils
          pkgs.glibc.bin
          pkgs.jq
          pkgs.sops
        ];
        text = # sh
          ''
                        repo=${userHome}/Projects/dots
                        stamp=${userHome}/.local/state/hass-state.sha256
                        [ -d "$repo/secrets" ] || exit 0
                        [ -d /var/lib/hass ] || exit 0

                        snapshot=/.snapshots/hass-backup
                        tmp=""
                        drop_snapshot() {
                          if [ -e "$snapshot" ]; then btrfs subvolume delete "$snapshot" >/dev/null; fi
                        }
                        cleanup() { drop_snapshot || true; if [ -n "$tmp" ]; then rm -rf "$tmp"; fi; }
                        drop_snapshot
                        trap cleanup EXIT
                        btrfs subvolume snapshot -r /var "$snapshot" >/dev/null

                        tmp=$(mktemp -d)
                        mkdir "$tmp/state"
                        cd "$snapshot/lib"
                        {
                          find hass -maxdepth 1 -type f \( -name '*.yaml' ! -name configuration.yaml -o -name 'zigbee.db' -o -name 'zigbee.db-wal' \)
                          find hass/.storage -type f ! -name 'core.restore_state' ! -name 'trace.saved_traces' ! -name 'bluetooth.*' ! -name '*.bak*'
                          if [ -d private/matterjs-server ]; then find private/matterjs-server -type f; fi
                        } | while IFS= read -r p; do
                          mkdir -p "$tmp/state/$(dirname "$p")"
                          if iconv -f utf-8 -t utf-8 "$p" >/dev/null 2>&1; then
                            cp "$p" "$tmp/state/$p"
                          else
                            base64 -w0 "$p" > "$tmp/state/$p.base64"
                          fi
                        done
                        cd /
                        drop_snapshot

                        sum=$(
                          cd "$tmp/state" &&
                            find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
                        )
                        [ "$sum" != "$(cat "$stamp" 2>/dev/null || true)" ] || exit 0

                        # sops's EDITOR path keeps the ciphertext of unchanged leaves, so
                        # a git diff shows only the files that changed.
                        cat > "$tmp/update-state" <<'EDITOR'
            #!/bin/sh
            f=$1
            printf '{}\n' > "$f"
            find "$STATEDIR" -type f | LC_ALL=C sort | while IFS= read -r p; do
              k=''${p#"$STATEDIR"/}
              jq --arg k "$k" --rawfile v "$p" '.[$k] = $v' "$f" > "$f.new" && mv "$f.new" "$f"
            done
            EDITOR
                        chmod +x "$tmp/update-state"
                        cd "$repo"
                        rm -f secrets/.hass-state.tmp.json
                        if [ -f secrets/hass-state.json ]; then
                          cp -p secrets/hass-state.json secrets/.hass-state.tmp.json
                        fi
                        STATEDIR="$tmp/state" EDITOR="$tmp/update-state" sops secrets/.hass-state.tmp.json </dev/null
                        mv -f secrets/.hass-state.tmp.json secrets/hass-state.json
                        chown ${defaultUser}:users secrets/hass-state.json
                        mkdir -p "$(dirname "$stamp")"
                        echo "$sum" > "$stamp"
                        chown ${defaultUser}:users "$stamp"
                        echo "wrote $repo/secrets/hass-state.json"
          '';
      };
    in
    {
      environment.systemPackages = [ unpackState ];

      systemd.services.hass-backup = {
        description = "Back up Home Assistant state into the dots repo";
        environment.SOPS_AGE_KEY_FILE = "/etc/age/keys.txt";
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          ExecStart = lib.getExe backupState;
        };
      };

      systemd.timers.hass-backup = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          Persistent = true;
        };
      };
    };
}
