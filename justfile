override_args := '--override-input devenv-root $"file+file://(pwd)/.devenv/root"'

# `just system`
default:
    @just system

# apply current system config
system:
    #!/usr/bin/env nu
    let hostname = (hostname)
    match (uname | get kernel-name) {
      "Darwin" => {
        morlana switch --flake . --no-confirm -- --show-trace
        # Update result-{hostname} to match result
        if ("result" | path exists) {
          ln -sfn (readlink result) $"result-($hostname)"
        }
        null
      }
      "Linux" => {
        nh os switch . -o result
        # Update result-{hostname} to match result
        if ("result" | path exists) {
          ln -sfn (readlink result) $"result-($hostname)"
        }
      }
      _ => {
        error make { msg: "Unknown OS" }
      }
    }

# fix the lockfile for auto-follow
lock:
    nix flake lock
    nix run /home/x/Projects/nix-auto-follow -- -i --consolidate
    @sleep 1
    nix run /home/x/Projects/nix-auto-follow -- -c

# update all inputs
update:
    nix flake update

# update input nixpkgs-bleeding
bleed:
    nix flake lock --update-input nixpkgs-bleeding

# build praesidium nixos configuration with gc root (useful for remote builds on stella)
build-praesidium:
    nix build .#nixosConfigurations.praesidium.config.system.build.toplevel --out-link result-praesidium
    @mkdir -p /nix/var/nix/gcroots/per-user/$USER
    @ln -sfn $(pwd)/result-praesidium /nix/var/nix/gcroots/per-user/$USER/result-praesidium
    @echo "Built and created GC root: /nix/var/nix/gcroots/per-user/$USER/result-praesidium -> $(pwd)/result-praesidium"

# build stella darwin configuration with gc root (useful for remote builds on praesidium)
build-stella:
    nix build .#darwinConfigurations.stella.config.system.build.toplevel --out-link result-stella
    @mkdir -p /nix/var/nix/gcroots/per-user/$USER
    @ln -sfn $(pwd)/result-stella /nix/var/nix/gcroots/per-user/$USER/result-stella
    @echo "Built and created GC root: /nix/var/nix/gcroots/per-user/$USER/result-stella -> $(pwd)/result-stella"

# pretty-print outputs
show:
    #!/usr/bin/env nu
    (nix run github:DeterminateSystems/nix-src/flake-schemas --
      flake show . {{ override_args }})

# flake check current system
check:
    #!/usr/bin/env nu
    match (uname | get kernel-name) {
      "Darwin" => {
        # https://github.com/NixOS/nix/issues/4265#issuecomment-2477954746
        (nix flake check {{ override_args }}
          --override-input systems github:nix-systems/aarch64-darwin)
      }
      "Linux" => {
        nix flake check {{ override_args }}
      }
      _ => {
        error make { msg: "Unknown OS" }
      }
    }

# flake check all systems
check-all:
    #!/usr/bin/env nu
    (NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1
      nix flake check --impure --all-systems
      {{ override_args }})
