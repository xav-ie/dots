default:
    @just system

# TODO: refactor into a devshell
# allows extremely fast shell commands with fallbacks to nix
get command:
    #!/usr/bin/env nu
    let cmds_and_backups = {
      "darwin-rebuild": "nix-darwin"
      "morlana": "github:ryanccn/morlana"
      "nixos-rebuild": "nixpkgs#nixos-rebuild"
      "nom": "nixpkgs#nix-output-monitor"
      "nvd": "nixpkgs#nvd"
      "zenity": "nixpkgs#zenity"
    }

    let cmd = "{{ command }}"
    if $cmd not-in $cmds_and_backups {
      error make {msg: $"Unknown function: ($cmd)"}
    }

    let cmd_path = try { ^which $cmd err> /dev/null } catch { "" }
    if ($cmd_path | str length) > 0 {
      $cmd_path
    } else {
      print -e $"💡 Consider installing (ansi green)($cmd)(ansi reset) into your PATH"
      print -e $"   It will enable faster invocations"
      ^nix shell ($cmds_and_backups | get $cmd) --command sh -c $"which ($cmd)"
    }

# apply current system config
system:
    #!/usr/bin/env nu
    def pipefail [] {
      let results = complete
      match $results {
        {exit_code: 0} => $results.stdout,
        _ => (error make { msg: $results.stdout })
      }
    }
    match (uname | get kernel-name) {
      "Darwin" => {
        # (^(just get darwin-rebuild) switch --flake . --show-trace out+err>|
        #   tee { ^(just get nom) } | pipefail)
        ^(just get morlana) switch --flake . --no-confirm -- --show-trace

        launchctl list | split row -r '\n'
        | skip 1
        | split column --regex '\s+' PID Status Label
        | where Label =~ "^org.nixos" | each {|e|
          print $"🍃 Relaunching ($e.Label)"
          let agentPath = $"~/Library/LaunchAgents/($e.Label).plist"
          let launchGroup = $"gui/(id -u)"
          try { launchtl bootout $launchGroup $agentPath }
          try { launchtl bootstrap $launchGroup $agentPath }
        }
        null
      }
      "Linux" => {
        # # 1. build ./result for diffing
        (^(just get nixos-rebuild) build --flake . --show-trace
          out+err>| tee { ^(just get nom )} | pipefail)

        # # 2. diff it with current system
        ^(just get nvd) diff /run/current-system ./result

        # 3. ask for password after seeing diff
        try { sudo -nv err> /dev/null } catch {
          try {
            ^(just get zenity) --password | sudo -Sv err> /dev/null
          } catch {
            print -e $"(ansi yellow_underline)Failed to get a password through UI(ansi reset)"
          }
        }

        # 4. apply switch, does need nom since it is using ./result
        sudo (just get nixos-rebuild) switch --flake . --show-trace --fast

        # 5. post-switch checks
        let bad_settings = (systemctl --user list-unit-files --legend=false
                            | lines
                            | split column -r '\s+' unit state preset
                            | where unit !~ "@\\."
                            | each { |row|
                              let unit = $row.unit
                              let has_bad_setting = systemctl --user status $unit
                                                    | str contains 'bad-setting'
                              { unit: $unit, bad_setting: $has_bad_setting }
                            }
                            | where bad_setting == true)

        if ($bad_settings | length) > 0 {
          error make {msg: $"Bad settings found: ($bad_settings)"}
        } else {
          print "No bad units found!"
        }
      }
      _ => {
        print "Unknown OS"
      }
    }

# init:
#     nix run home-manager/master -- init --switch

# update nixpkgs-bleeding
bleed:
    nix flake lock --update-input nixpkgs-bleeding

# pretty-print outputs
show:
    nix run github:DeterminateSystems/nix-src/flake-schemas -- flake show .

# update all inputs
update:
    nix flake update

# `nix flake check` only works on nixos because of
# https://github.com/NixOS/nix/issues/4265
# The above command basically insists on checking things it does not have to.
# Here is excerpt from `nix flake check --help`:
# Evaluation checks
#     · checks.system.name
#     · defaultPackage.system
#     · devShell.system
#     · devShells.system.name
#     · nixosConfigurations.name.config.system.build.toplevel
#     · packages.system.name
# It would be cool to disable nixosConfigurations, but oh well. Maybe one day :).
# flake check current system
check:
    #!/usr/bin/env nu
    def pipefail [] {
      let results = complete
      match $results {
        {exit_code: 0} => $results.stdout,
        _ => (error make { msg: $results.stdout })
      }
    }
    match (uname | get kernel-name) {
      "Darwin" => {
        # This is the only way I know how to skip nixosConfigurations on darwin :/
        (nix flake check --override-input systems github:nix-systems/aarch64-darwin
          out+err>| tee { ^(just get nom ) } | pipefail)
      }
      "Linux" => {
        nix flake check out+err>| tee { ^(just get nom )} | pipefail
      }
      _ => {
        print "Unknown OS"
      }
    }
    # TODO: use treefmt instead
    nix run nixpkgs#deadnix -- -f # check for dead code, fails if any

# flake check all systems
check-all:
    NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nix flake check --impure --all-systems
