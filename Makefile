
.PHONY: docs
docs: README.norg
	nvim --headless -c "edit README.norg" -c "Neorg export to-file README.md" -c "q"

.PHONY: system
system:
	sudo nixos-rebuild switch --flake ~/Projects/mysystem

.PHONY: bleed
bleed:
	nix flake lock --update-input nixpkgs-bleeding

.PHONY: update
update:
	nix flake update
