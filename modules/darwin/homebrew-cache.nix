{
  # Cache brew bundle execution - only run when Brewfile changes
  flake.modules.darwin.macos =
    { config, lib, ... }:
    let
      cfg = config.homebrew;
      cacheDir = "/var/lib/nix-darwin-homebrew";
      brewfileHash = cfg.brewfile |> builtins.hashString "sha256";
    in
    {
      config = lib.mkIf cfg.enable {
        # Override the default homebrew activation to add caching
        system.activationScripts.homebrew.text =
          lib.mkForce # sh
            ''
              # Re-link the prefix/taps/engine every activation (idempotent
              # ln -shf). Guarding this behind "brew not installed" meant flake
              # bumps changed store paths but never re-pointed /opt/homebrew, so
              # brew bundle kept running the stale engine/tap.
              ${config.system.activationScripts.setup-homebrew.text}

              # Homebrew Bundle (with caching)
              echo >&2 "Homebrew bundle..."

              CACHE_FILE="${cacheDir}/brewfile-hash"
              CURRENT_HASH="${brewfileHash}"

              if [ -f "${cfg.prefix}/bin/brew" ]; then
                mkdir -p "${cacheDir}"

                if [ -f "$CACHE_FILE" ] && [ "$(cat "$CACHE_FILE")" = "$CURRENT_HASH" ]; then
                  echo >&2 "Brewfile unchanged, skipping brew bundle..."
                else
                  echo >&2 "Brewfile changed, running brew bundle..."
                  ${cfg.onActivation.brewBundleCmd { onlyCheck = false; }}
                  echo "$CURRENT_HASH" > "$CACHE_FILE"
                fi
              else
                echo -e "\e[1;31merror: Homebrew is not installed, skipping...\e[0m" >&2
              fi
            '';
      };
    };
}
