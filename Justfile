# List available commands by default
default:
    @just system

# allows extremely fast shell commands with fallbacks to nix
invoke function *args:
    #!/usr/bin/env nu
    def shell_command [cmd: list<string>, cmd_backup: list<string>, args: list<string> = []] {
      # the exernal `which` seems to resolve better...
      let cmd_path = try { (^which ($cmd | first)) | lines | first } catch { "" }
      if ($cmd_path | str length) > 0 {
        sh -c ($args | prepend $cmd | str join " ")
      } else {
        print $"💡 Consider installing (ansi green)($cmd | first)(ansi reset) into your PATH"
        print $"   It will enable faster invocations"
        sh -c ($args | prepend $cmd_backup | str join " ")
      }
    }

    def darwin_rebuild [args: list<string> = []] {
      shell_command [darwin-rebuild] [nix shell nix-darwin --command darwin-rebuild] $args
    }
    def morlana [args: list<string> = []] {
      shell_command [morlana] [nix shell "github:ryanccn/morlana" --command morlana] $args
    }
    def nixos_rebuild [args: list<string> = []] {
      shell_command [nixos-rebuild] [nix shell "nixpkgs#nixos-rebuild" --command nixos-rebuild] $args
    }
    def nom [args: list<string> = []] {
      shell_command [nom] [nix shell "nixpkgs#nix-output-monitor" --command nom] $args
    }

    match "{{ function }}" {
      "darwin-rebuild" => { darwin_rebuild [{{ args }}] }
      "morlana" => { morlana [{{ args }}] }
      "nixos-rebuild" => { nixos_rebuild [{{ args }}] }
      "nom" => { nom [{{ args }}] }
      _ => { error make {msg: "Unknown function: {{ function }}"} }
    }

system:
    #!/usr/bin/env nu
    def launchctl_list [] {
      launchctl list | split row -r '\n'
      | skip 1
      | split column --regex '\s+' PID Status Label
    }
    def pipefail [] {
      let results = complete
      match $results {
        {exit_code: 0} => $results.stdout,
        _ => (error make { msg: $results.stdout })
      }
    }

    match (uname | get kernel-name) {
      "Darwin" => {
        # just invoke darwin-rebuild switch --flake . --show-trace out+err>| tee { just invoke nom } | pipefail
        just invoke morlana switch --flake . --no-confirm -- --show-trace
        # TODO: relaunch hm services?
        launchctl_list | where Label =~ "^org.nixos" | each {|e|
          print $"🍃 Relaunching ($e.Label)"
          let agentPath = $"~/Library/LaunchAgents/($e.Label).plist"
          let launchGroup = $"gui/(id -u)"
          try { launchtl bootout $launchGroup $agentPath }
          try { launchtl bootstrap $launchGroup $agentPath }
        }
        null
      }
      "Linux" => {
        just invoke nixos-rebuild switch --flake . --show-trace out+err>| tee { just invoke nom } | pipefail

        print "Checking for bad systemd user units..."
        let bad_settings = (systemctl --user list-unit-files --legend=false
                            | lines
                            | split column -r '\s+' unit state preset
                            | where unit !~ "@\\."
                            | each {|row|
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

init:
    #!/usr/bin/env nu
    nix run home-manager/master -- init --switch

bleed:
    #!/usr/bin/env nu
    nix flake lock --update-input nixpkgs-bleeding

update:
    #!/usr/bin/env nu
    nix flake update

diff:
    #!/usr/bin/env nu
    nix run nixpkgs#nvd -- diff /run/booted-system /run/current-system

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
check:
    #!/usr/bin/env nu
    match (uname | get kernel-name) {
      "Darwin" => {
        # This is the only way I know how to skip nixosConfigurations on darwin :/
        nix flake check --override-input systems github:nix-systems/aarch64-darwin
      }
      "Linux" => {
        nix flake check
      }
      _ => {
        print "Unknown OS"
      }
    }
    # TODO: use treefmt instead
    nix run nixpkgs#deadnix -- -f # check for dead code, fails if any

check-all:
    #!/usr/bin/env nu
    NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nix flake check --impure --all-systems
