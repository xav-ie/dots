{
  config,
  lib,
  ...
}:
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

          find "$newGenFiles" \( -type f -or -type l \) -print0 | while IFS= read -r -d "" sourcePath; do
            relativePath="''${sourcePath#$newGenFiles/}"
            targetPath="$HOME/$relativePath"

            # Skip if symlink already correct
            if [[ -L "$targetPath" && "$(readlink "$targetPath")" == "$sourcePath" ]]; then
              continue
            fi

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
  };
}
