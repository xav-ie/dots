.PHONY: system
system:
ifeq ($(shell uname -s), Darwin)
	darwin-rebuild switch --flake .
else
	sudo nixos-rebuild switch --impure --flake .
	@echo "Checking for bad systemd user units..."
	systemctl --user list-unit-files | awk '{print $1}' | while read unit; do systemctl --user status "$unit" 2>&1 | grep -q 'bad-setting' && echo "Bad setting in $unit" || true; done
endif

# if using home-manager externally to config
# home-manager switch

# buggy
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
