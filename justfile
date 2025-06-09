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
        # 1. build ./result for diffing
        (nixos-rebuild build --flake . --fast
          --show-trace --log-format internal-json
          out+err>| nom --json)

        # 2. diff it with current system
        nvd diff /run/current-system ./result
        # TODO: contribute a better diff output... quite ugly
        # nix-diff /run/current-system ./result

        # 3. ask for password after seeing diff
        try { sudo -nv err> /dev/null } catch {
          try {
            zenity --password | sudo -Sv err> /dev/null
          } catch {
            print -e ...[
              (ansi yellow_underline)
              "Failed to get a password through UI"
              (ansi reset)
            ]
          }
        }

        # 4. apply switch, does need nom since it is using ./result
        sudo ./result/bin/switch-to-configuration switch

        # 5. post-switch checks
        let bad_settings = (systemctl --user list-unit-files --legend=false
                           | lines
                           | split column -r '\s+' unit state preset
                           | where unit !~ "@\\."
                           | get unit
                           | par-each { |unit|
                             {
                               unit: $unit,
                               bad_setting: (
                                 systemctl --user status $unit
                                 | str contains 'bad-setting'
                               )
                             }
                           }
                           | where bad_setting == true)

        if ($bad_settings | length) > 0 {
          error make {msg: $"Bad settings found: ($bad_settings)"}
        } else {
          print "No bad units found!"
        }
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
