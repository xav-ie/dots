# `just system`
default:
    @just system

# apply current system config
system:
    #!/usr/bin/env nu
    match (uname | get kernel-name) {
      "Darwin" => {
        morlana switch --flake . --no-confirm -- --show-trace
        null
      }
      "Linux" => {
        nh os build .
        # get password through askpass program
        try { sudo -A true }
        nh os switch .
      }
      _ => {
        error make { msg: "Unknown OS" }
      }
    }

# update all inputs
update:
    nix flake update

# update input nixpkgs-bleeding
bleed:
    nix flake lock --update-input nixpkgs-bleeding

# pretty-print outputs
show:
    #!/usr/bin/env nu
    let override_args = [
      "--override-input" "devenv-root" $"file+file://(pwd)/.devenv/root"
    ]
    (nix run github:DeterminateSystems/nix-src/flake-schemas --
      flake show . ...$override_args)

# flake check current system
check:
    #!/usr/bin/env nu
    let override_args = [
      "--override-input" "devenv-root" $"file+file://(pwd)/.devenv/root"
    ]
    match (uname | get kernel-name) {
      "Darwin" => {
        # https://github.com/NixOS/nix/issues/4265#issuecomment-2477954746
        (nix flake check ...$override_args
          --override-input systems github:nix-systems/aarch64-darwin)
      }
      "Linux" => {
        nix flake check ...$override_args
      }
      _ => {
        error make { msg: "Unknown OS" }
      }
    }

# flake check all systems
check-all:
    #!/usr/bin/env nu
    let override_args = [
      "--override-input" "devenv-root" $"file+file://(pwd)/.devenv/root"
    ]
    (NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1
      nix flake check --impure --all-systems
      ...$override_args)
