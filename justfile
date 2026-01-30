# `just system`
default:
    @just system

# apply current system config
system:
    #!/usr/bin/env nu

    # Run commands in parallel, streaming all output live (unbuffered)
    def stream-parallel []: list<string> -> list<record> {
      par-each {|cmd|
        bash -c $"stdbuf -o0 ($cmd)"
        | tee { print -n } e>| tee -e { print -n }
        | complete
        | { cmd: $cmd, ...$in }
      }
    }

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
        nh os build . -o result -- --show-trace
        let cursor = (journalctl -u $"home-manager-($env.USER).service" -n 0 --show-cursor | lines | last | str replace "-- cursor: " "")

        let results = [
          $"nh os switch . -o result -- --show-trace"
          $"journalctl -f -u home-manager-($env.USER).service --after-cursor '($cursor)' --no-pager -o cat | stdbuf -o0 sed '/Finished Home Manager/q'"
        ] | stream-parallel

        if ($results | first).exit_code != 0 {
          error make { msg: "Switch failed" }
        }
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
