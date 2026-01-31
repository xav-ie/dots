{
  config,
  lib,
  ...
}:
let
  # Collect all paths with force = true (from home.file, xdg.configFile, etc.)
  forcedPaths = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (_name: file: file.target) (
      lib.filterAttrs (_name: file: file.force) config.home.file
    )
  );
in
{
  options.programs.linkOptimization.enable =
    lib.mkEnableOption "skip already-correct symlinks during linking"
    // {
      default = true;
    };

  config = lib.mkIf config.programs.linkOptimization.enable {
    home.activation.linkGeneration = lib.mkForce (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        function linkNewGen() {
          _i "Creating home file links in %s" "$HOME"
          local newGenFiles
          newGenFiles="$(readlink -e "$newGenPath/home-files")"

          local linked_files=""
          find "$newGenFiles" \( -type f -or -type l \) -print0 | while IFS= read -r -d "" sourcePath; do
            relativePath="''${sourcePath#$newGenFiles/}"
            targetPath="$HOME/$relativePath"

            # Skip if symlink already correct
            if [[ -L "$targetPath" && "$(readlink "$targetPath")" == "$sourcePath" ]]; then
              continue
            fi

            echo "  linking: $relativePath" >&2
            run mkdir -p "$(dirname "$targetPath")"
            run ln -Tsf "$sourcePath" "$targetPath"
          done
        }

        function cleanOldGen() {
          [[ ! -v oldGenPath || ! -e "$oldGenPath/home-files" ]] && return
          _i "Cleaning up orphan links from %s" "$HOME"
          local newGenFiles oldGenFiles
          newGenFiles="$(readlink -e "$newGenPath/home-files")"
          oldGenFiles="$(readlink -e "$oldGenPath/home-files")"

          find "$oldGenFiles" \( -type f -or -type l \) -print0 | while IFS= read -r -d "" sourcePath; do
            relativePath="''${sourcePath#$oldGenFiles/}"
            [[ -e "$newGenFiles/$relativePath" ]] && continue
            targetPath="$HOME/$relativePath"
            [[ "$(readlink "$targetPath")" == /nix/store/* ]] && run rm "$targetPath"
          done
        }

        cleanOldGen
        linkNewGen
      ''
    );

    home.activation.checkLinkTargets = lib.mkForce (
      lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        function checkNewGenCollision() {
          local newGenFiles
          newGenFiles="$(readlink -e "$newGenPath/home-files")"
          local homeFilePattern="/nix/store/*-home-manager-files/*"

          # Build associative array of forced paths for O(1) lookup
          declare -A forcedPathsMap
          while IFS= read -r p; do
            [[ -n "$p" ]] && forcedPathsMap["$p"]=1
          done <<'FORCED_PATHS'
        ${forcedPaths}
        FORCED_PATHS

          # Temp files for parallel results
          local collision_errors=$(mktemp)
          local collision_warnings=$(mktemp)

          # Use process substitution to avoid subshell from pipe
          while IFS= read -r -d "" sourcePath; do
            relativePath="''${sourcePath#$newGenFiles/}"
            targetPath="$HOME/$relativePath"

            # Skip if force = true for this path
            [[ -v "forcedPathsMap[$relativePath]" ]] && continue

            # Check in background
            (
              if [[ -e "$targetPath" ]]; then
                linkTarget=$(readlink "$targetPath" 2>/dev/null || true)
                if [[ ! "$linkTarget" == $homeFilePattern ]]; then
                  # Not a home-manager symlink - check if contents match
                  if cmp -s "$sourcePath" "$targetPath"; then
                    echo "Existing file '$targetPath' is in the way of '$sourcePath', will be skipped since they are the same" >> "$collision_warnings"
                  else
                    echo "Existing file '$targetPath' would be clobbered by '$sourcePath'" >> "$collision_errors"
                  fi
                fi
              fi
            ) &
          done < <(find "$newGenFiles" \( -type f -or -type l \) -print0)
          wait

          # Print warnings
          if [[ -s "$collision_warnings" ]]; then
            while IFS= read -r warning; do
              warnEcho "$warning"
            done < "$collision_warnings"
          fi

          # Check for errors
          if [[ -s "$collision_errors" ]]; then
            errorEcho "Please set 'force = true' on the related file options to forcefully overwrite"
            while IFS= read -r error; do
              errorEcho "$error"
            done < "$collision_errors"
            rm -f "$collision_errors" "$collision_warnings"
            return 1
          fi

          rm -f "$collision_errors" "$collision_warnings"
        }

        checkNewGenCollision || exit 1
      ''
    );
  };
}
