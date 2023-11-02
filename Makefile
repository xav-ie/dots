.PHONY: init
init:
	nix run home-manager/master -- init --switch

.PHONY: docs
docs: README.norg
	nvim --headless -c "edit README.norg" -c "Neorg export to-file README.md" -c "q"

.PHONY: system
system:
	sudo nixos-rebuild switch --flake ~/Projects/mysystem
	# home-manager switch

.PHONY: bleed
bleed:
	nix flake lock --update-input nixpkgs-bleeding

.PHONY: update
update:
	nix flake update
