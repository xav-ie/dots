
.PHONY: docs
docs: README.norg
	nvim --headless -c "edit README.norg" -c "Neorg export to-file README.md" -c "q"

.PHONY: system
system:
	sudo nixos-rebuild switch --flake ~/Projects/mysystem

INPUTS = nixpkgs nur
.PHONY: update
update:
	for input in $(INPUTS); do \
		nix flake lock --update-input $$input; \
	done
