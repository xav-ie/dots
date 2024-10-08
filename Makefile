.PHONY: system
system:
ifeq ($(shell uname -s), Darwin)
	darwin-rebuild switch --flake .
	# TODO: add full macos equivalent
	# relaunch skhd
	sudo launchctl bootout gui/$(shell id -u) ~/Library/LaunchAgents/org.nixos.skhd.plist && sudo launchctl bootstrap gui/$(shell id -u) ~/Library/LaunchAgents/org.nixos.skhd.plist
else
	sudo nixos-rebuild switch --flake .
	@echo "Checking for bad systemd user units..."
	systemctl --user list-unit-files | awk '{print $1}' | while read unit; do systemctl --user status "$unit" 2>&1 | grep -q 'bad-setting' && echo "Bad setting in $unit" || true; done
endif

# if using home-manager externally to config
# home-manager switch

# buggy, be careful to only run this for bootstrapping.
.PHONY: init
init:
	nix run home-manager/master -- init --switch

.PHONY: docs
docs: README.norg
	nvim --headless -c "edit README.norg" -c "Neorg export to-file README.md" -c "q"

.PHONY: bleed
bleed:
	nix flake lock --update-input nixpkgs-bleeding

.PHONY: update
update:
	nix flake update

# TODO: make this work on macos
.PHONY: diff
diff:
	nix run nixpkgs\#nvd -- diff /run/booted-system /run/current-system

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
.PHONY: check
check:
	nix flake check
	nix run nixpkgs#deadnix -- -f # check for dead code, fails if any

.PHONY: check-all
check-all:
	NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM=1 nix flake check --impure --all-systems
