# Cache brew bundle execution - only run when Brewfile changes
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.homebrew;
  cacheDir = "/var/lib/nix-darwin-homebrew";
  brewfileHash = builtins.hashString "sha256" cfg.brewfile;
in
{
  config = lib.mkIf cfg.enable {
    # Override the default homebrew activation to add caching
    system.activationScripts.homebrew.text = lib.mkForce ''
      # Homebrew Bundle (with caching)
      echo >&2 "Homebrew bundle..."

      CACHE_FILE="${cacheDir}/brewfile-hash"
      CURRENT_HASH="${brewfileHash}"

      if [ -f "${cfg.brewPrefix}/brew" ]; then
        # Create cache directory if it doesn't exist
        mkdir -p "${cacheDir}"

        # Check if we need to run brew bundle
        if [ -f "$CACHE_FILE" ] && [ "$(cat "$CACHE_FILE")" = "$CURRENT_HASH" ]; then
          echo >&2 "Brewfile unchanged, skipping brew bundle..."
        else
          echo >&2 "Brewfile changed, running brew bundle..."
          PATH="${cfg.brewPrefix}:${lib.makeBinPath [ pkgs.mas ]}:$PATH" \
          sudo \
            --preserve-env=PATH \
            --user=${lib.escapeShellArg cfg.user} \
            --set-home \
            env \
            ${cfg.onActivation.brewBundleCmd}

          # Save the hash on success
          echo "$CURRENT_HASH" > "$CACHE_FILE"
        fi
      else
        echo -e "\e[1;31merror: Homebrew is not installed, skipping...\e[0m" >&2
      fi
    '';
  };
}
