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
        # `nh os switch` only writes the boot entry once activation succeeds, so
        # one failed unit leaves a live generation the next reboot can't reach.
        # Boot first, then activate; nu stops here if boot fails.
        nh os boot . -o result -- --show-trace
        nh os test . -o result -- --show-trace
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

# reboot once into the `autologin` specialisation, which skips the greeter and
# comes up straight in Hyprland — for rebooting a machine you're not sitting at.

# Only that one boot is passwordless; every boot after it uses the greeter again.
reboot-auto-login:
    #!/usr/bin/env nu
    if (uname | get kernel-name) != "Linux" {
      error make { msg: "NixOS only" }
    }

    just system

    # bootctl needs root: the ESP is mode 0700 (see nixos/hardware-configuration.nix).
    let entries = (
      sudo bootctl list --json=short
      | from json
      | where ($it.id | str contains "specialisation-autologin")
      | insert gen { $in.id | parse -r 'generation-(?<n>\d+)' | get n.0 | into int }
      | sort-by gen
    )
    if ($entries | is-empty) {
      error make { msg: "no autologin specialisation boot entry — did `just system` succeed?" }
    }
    let entry = ($entries | last)

    print $"Will reboot into: ($entry.id)"
    if (input "Type 'yes' to reboot: ") != "yes" {
      error make { msg: "aborted" }
    }
    sudo systemctl reboot $"--boot-loader-entry=($entry.id)"

# refresh the lockfile
lock:
    #!/usr/bin/env nu
    # direnv is denied for the write and re-allowed even on failure: a bare
    # `direnv allow` as the last line leaves the repo denied whenever something
    # above it fails.
    direnv deny
    let err = (try { nix flake lock; null } catch { |e| $e.msg })
    direnv allow
    if $err != null { error make { msg: $"just lock failed: ($err)" } }

# Writes follows into flake.nix source, not the lock: a follows that no
# flake.nix declares reads as absent and is recomputed from the declared URL,
# so rewriting only the lock is undone by the next `nix flake lock`.
#
# Deliberately NOT part of `just lock`. It rewrites declarations and cannot
# tell an intentional exception from an oversight: it re-adds a follows removed
# on purpose (nufmt pins rustPackages by name, so it must keep its own nixpkgs)
# and drops overrides it sees no lock evidence for (alacritty-theme).
#
# collapse duplicated inputs onto top-level ones -- review the diff after
dedupe:
    #!/usr/bin/env nu
    # `--inputs-from .` takes flake-edit from this flake's own nixpkgs, so this
    # does not depend on the devshell.
    nix run --inputs-from . nixpkgs#flake-edit -- follow --transitive
    nix flake lock
    print "\nReview `git diff flake.nix` before keeping this."

# update all inputs
update:
    #!/usr/bin/env nu
    # Unauthenticated, api.github.com rate-limits at ~60/hr and nix answers a
    # 403 by silently reusing its *cached* HEAD — so inputs appear up to date
    # while actually being pinned days behind, with no non-zero exit.
    nix flake update --option access-tokens $"github.com=(gh auth token)"

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

# refresh the Slack MCP tokens (xoxc/xoxd) in sops. These are Slack
# browser-session tokens and expire periodically; when they do, slack-mcp-server
# dies on startup. Read them out of any browser signed into the workspace — your
# laptop's is fine — and paste them here. Prompted rather than taken as arguments

# so the tokens stay out of shell history. Run `just` after.
slack-tokens:
    #!/usr/bin/env nu
    print "In a browser signed into Slack, open https://app.slack.com and press F12."
    print ""
    print "xoxc — Console tab, paste this and copy the result:"
    print ""
    print "    Object.values(JSON.parse(localStorage.localConfig_v2).teams)[0].token"
    print ""
    let xoxc = (input "  paste xoxc: " | str trim)
    print ""
    print "xoxd — Application tab -> Storage -> Cookies -> https://app.slack.com -> `d`."
    print "(HttpOnly, so the console can't read it. Copy the Value column.)"
    print ""
    let raw = (input "  paste xoxd: " | str trim)
    print ""

    # DevTools shows the cookie percent-encoded; the token itself never contains
    # a literal `%`, so its presence is what distinguishes the two forms.
    let xoxd = if ($raw | str contains "%") { $raw | url decode } else { $raw }

    if not ($xoxc | str starts-with "xoxc-") {
      error make { msg: $"that is not an xoxc- token \(got '($xoxc | str substring 0..8)'\)" }
    }
    if not ($xoxd | str starts-with "xoxd-") {
      error make { msg: $"that is not an xoxd- token \(got '($xoxd | str substring 0..8)'\)" }
    }

    print $"  xoxc ($xoxc | str substring 0..12)…   xoxd ($xoxd | str substring 0..12)…"
    sudo sops set secrets/main.yaml '["slack"]["xoxc_token"]' $'"($xoxc)"'
    sudo sops set secrets/main.yaml '["slack"]["xoxd_token"]' $'"($xoxd)"'
    print "Updated Slack tokens in secrets/main.yaml. Run `just` to re-render + restart the proxy."

# Secrets are rendered from sops into ~/.cache/esphome, which is kept 0700
# rather than cleaned up: the compile cache there embeds the same secrets
# anyway, and keeping it makes rebuilds fast.

# compile + flash esphome/<device>.yaml over USB or OTA (it asks which port)
esphome device="colorshadowrgb":
    #!/usr/bin/env nu
    let dir = ($env.HOME | path join ".cache" "esphome")
    mkdir $dir
    chmod 700 $dir
    # Reuse the NetworkManager PSK (modules/nixos/wifi-failover.nix) so there is one copy.
    let psk = (sudo sops -d --extract '["wifi"]["env"]' secrets/main.yaml
      | lines | parse "{k}={v}" | where k == "VERIZON_JKST69_PSK" | get v.0 | str trim -c '"')
    sudo sops -d secrets/esphome.yaml | from yaml | merge { wifi_password: $psk }
      | to yaml | save -f ($dir | path join "secrets.yaml")
    cp -f "esphome/{{ device }}.yaml" $dir
    # In the official container: nixpkgs' esphome can't compile, because PlatformIO
    # downloads a generic-Linux ESP-IDF toolchain that doesn't run on NixOS.
    # keep-groups carries dialout in so rootless podman can open the serial port;
    # host network is for OTA/mDNS.
    let devices = (glob /dev/ttyACM* | each {|d| [--device $d] } | flatten)
    (podman run --rm -it --network host --group-add keep-groups ...$devices
      -v $"($dir):/config" ghcr.io/esphome/esphome:stable run "/config/{{ device }}.yaml")

# Rotating the keypair drops every phone's push subscription, so each has to
# re-enable push.

# generate Collie's Web Push (VAPID) keypair into sops; run `just` after
collie-vapid:
    #!/usr/bin/env nu
    let cli = (nix build .#collie --no-link --print-out-paths | str trim) + "/share/collie/node_modules/web-push/src/cli.js"
    let keys = (nix shell nixpkgs#nodejs -c node $cli generate-vapid-keys --json | from json)
    sudo sops set secrets/main.yaml '["collie"]["vapid_public"]' ($keys.publicKey | to json)
    sudo sops set secrets/main.yaml '["collie"]["vapid_private"]' ($keys.privateKey | to json)
    print "Stored Collie VAPID keys in secrets/main.yaml. Run `just` to apply."
