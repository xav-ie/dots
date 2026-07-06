# Enable pipe operators (|>) for every recipe's nix evaluation, including on a
# fresh system whose /etc/nix/nix.conf hasn't gained the feature yet. `extra-`
# appends, so nix-command/flakes from the system config are preserved.

export NIX_CONFIG := "extra-experimental-features = pipe-operators"

# `just system`
default:
    @just system

# apply current system config
system:
    #!/usr/bin/env nu
    let hostname = (hostname)

    # start: pin devshell to gc-roots
    let gc_root_name = "result-system-devshell"
    let devshell_job = job spawn {
      let system = (nix eval --raw --impure --expr "builtins.currentSystem")
      nix build $".#devShells.($system).default" --out-link $gc_root_name
    }

    match (uname | get kernel-name) {
      "Darwin" => {
        morlana switch --flake . --no-confirm -- --show-trace --out-link result
      }
      "Linux" => {
        nh os switch . -o result -- --show-trace
      }
      _ => {
        error make { msg: "Unknown OS" }
      }
    }

    # Update result-{hostname} to match result
    if ("result" | path exists) {
      ln -sfn (readlink result) $"result-($hostname)"
    }

    # cleanup: pin devshell to gc-roots
    while (job list | where id == $devshell_job | length) == 1 {
      print "Waiting for devshell job to finish..."
      sleep 1sec
    }
    (ln -sfn $"(pwd)/($gc_root_name)"
      $"/nix/var/nix/gcroots/per-user/($env.USER)/($gc_root_name)")

# fix the lockfile for auto-follow
lock:
    direnv deny
    nix flake lock
    nom-run ../nix-auto-follow -- -i --consolidate
    nom-run ../nix-auto-follow -- -c
    direnv allow

# update all inputs
update:
    nix flake update

# update input nixpkgs-bleeding
bleed:
    nix flake update nixpkgs-bleeding
    just lock

# build praesidium nixos configuration with gc root (useful for remote builds on nox)
build-praesidium:
    nom build .#nixosConfigurations.praesidium.config.system.build.toplevel --out-link result-praesidium
    @mkdir -p /nix/var/nix/gcroots/per-user/$USER
    @ln -sfn $(pwd)/result-praesidium /nix/var/nix/gcroots/per-user/$USER/result-praesidium
    @echo "Built and created GC root: /nix/var/nix/gcroots/per-user/$USER/result-praesidium -> $(pwd)/result-praesidium"

# build nox darwin configuration with gc root (useful for remote builds on praesidium)
build-nox:
    nom build .#darwinConfigurations.nox.config.system.build.toplevel --out-link result-nox
    @mkdir -p /nix/var/nix/gcroots/per-user/$USER
    @ln -sfn $(pwd)/result-nox /nix/var/nix/gcroots/per-user/$USER/result-nox
    @echo "Built and created GC root: /nix/var/nix/gcroots/per-user/$USER/result-nox -> $(pwd)/result-nox"

# pretty-print outputs
show:
    #!/usr/bin/env nu
    (nom-run github:DeterminateSystems/nix-src/flake-schemas --
      flake show .)

# flake check current system
check:
    #!/usr/bin/env nu
    match (uname | get kernel-name) {
      "Darwin" => {
        # https://github.com/NixOS/nix/issues/4265#issuecomment-2477954746
        (nix flake check
          --override-input systems github:nix-systems/aarch64-darwin)
      }
      "Linux" => {
        nix flake check
      }
      _ => {
        error make { msg: "Unknown OS" }
      }
    }

# flake check all systems
check-all:
    #!/usr/bin/env nu
    (NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1
      nix flake check --impure --all-systems)

# Re-establish the systemd notification-center daemon as sole owner of the
# org.freedesktop.Notifications bus. AstalNotifd proxies (e.g. the bar's
# `notifctl -swb`) queue for the name, so a stray can squat it and make
# `systemctl restart` a no-op. Stops the bar, kills every notification-center
# package gjs process (single PIDs — never a process group, which would take

# Hyprland down with it), starts the service, then brings the bar back.
notifd-reset:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "stopping bar + notification-center..."
    systemctl --user stop bar notification-center 2>/dev/null || true
    sleep 1.5
    echo "killing notification-center-package gjs processes (single PIDs)..."
    for g in $(pgrep -x gjs 2>/dev/null) $(pgrep -x gjs-console 2>/dev/null); do
      pp=$(awk '/^PPid:/{print $2}' "/proc/$g/status" 2>/dev/null || true)
      pcmd=$(tr '\0' ' ' < "/proc/$pp/cmdline" 2>/dev/null || true)
      case "$pcmd" in
        *-notification-center/bin/*) echo "  kill $g"; kill "$g" 2>/dev/null || true ;;
      esac
    done
    sleep 1
    echo "starting the systemd daemon..."
    systemctl --user reset-failed notification-center 2>/dev/null || true
    systemctl --user start notification-center
    sleep 2
    echo "notification-center: $(systemctl --user is-active notification-center)"
    echo "restarting bar..."
    systemctl --user reset-failed bar 2>/dev/null || true
    systemctl --user start bar
    echo "done — daemon owner:"
    busctl --user status org.freedesktop.Notifications 2>/dev/null | grep -E '^(PID|Comm)=' || true

# run the Firefox PiP mover tests: TS geometry/animation (vitest) + Rust client
test-pip:
    #!/usr/bin/env bash
    set -euo pipefail
    cd packages/firefox-pip-mover
    npm install --no-audit --no-fund
    npm run typecheck
    npm test
    cd ../move-pip
    nix shell nixpkgs#rustc -c rustc --test --edition 2021 \
      --crate-name move_pip_test move-pip.rs -o /tmp/move-pip-test
    /tmp/move-pip-test

# refresh the Slack MCP tokens (xoxc/xoxd) from the Firefox "Work" profile into
# sops. These are Slack browser-session tokens and expire periodically; when they
# do, slack-mcp-server dies on startup. xoxd is the HttpOnly `d` cookie (read from
# cookies.sqlite); xoxc lives in localStorage (snappy-compressed on disk), so it's

# grabbed via a console snippet that copies it to the clipboard. Run `just` after.
slack-tokens:
    #!/usr/bin/env nu
    let workdir = (firefox-router --profile-dir Work | str trim)
    if ($workdir | is-empty) or (not ($workdir | path exists)) {
      error make { msg: $"could not resolve the Firefox 'Work' profile: '($workdir)'" }
    }

    # Open Slack in the Work profile so the session is live/fresh.
    job spawn { firefox --profile $workdir --profiles-activate "https://app.slack.com/" | ignore }
    print $"Opened Slack in the Work profile \(($workdir | path basename)\)."
    print ""
    print "In the Slack tab: open DevTools (F12) -> Console and paste this (copies xoxc to your clipboard):"
    print ""
    print "    copy(Object.values(JSON.parse(localStorage.localConfig_v2).teams)[0].token)"
    print ""
    input "Then press Enter here to continue..."
    let xoxc = (wl-paste | str trim)

    # xoxd = the HttpOnly `d` cookie (not reachable from JS). Copy the DB + its WAL
    # sidecars so a freshly-written cookie isn't missed, then read + URL-decode it.
    let py = r#'import sys,os,sqlite3,urllib.parse,tempfile,shutil; wp=sys.argv[1]; d=tempfile.mkdtemp(); [shutil.copy2(os.path.join(wp,"cookies.sqlite"+e),os.path.join(d,"cookies.sqlite"+e)) for e in ("","-wal","-shm") if os.path.exists(os.path.join(wp,"cookies.sqlite"+e))]; c=sqlite3.connect(os.path.join(d,"cookies.sqlite")); r=c.execute("SELECT value FROM moz_cookies WHERE host LIKE '%slack.com' AND name='d'").fetchone(); print(urllib.parse.unquote(r[0]) if r else "")'#
    let xoxd = (python3 -c $py $workdir | str trim)

    if not ($xoxc | str starts-with "xoxc-") {
      error make { msg: $"clipboard is not an xoxc- token \(got '($xoxc | str substring 0..8)'\). Re-run the console snippet, then retry." }
    }
    if not ($xoxd | str starts-with "xoxd-") {
      error make { msg: "no valid xoxd- `d` cookie in the Work profile — are you logged into Slack there?" }
    }

    print $"  xoxc ($xoxc | str substring 0..12)…   xoxd ($xoxd | str substring 0..12)…"
    sudo sops set secrets/main.yaml '["slack"]["xoxc_token"]' $'"($xoxc)"'
    sudo sops set secrets/main.yaml '["slack"]["xoxd_token"]' $'"($xoxd)"'
    print "Updated Slack tokens in secrets/main.yaml. Run `just` to re-render + restart the proxy."
