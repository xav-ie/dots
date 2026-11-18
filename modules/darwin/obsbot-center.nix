# OBSBOT Center (webcam control app). Its virtual camera is a system extension,
# which macOS only activates for apps in /Applications, so activation copies the
# store bundle there instead of linking it. ditto keeps OBSBOT's signature, and the
# copy is redone only when the package changes.
{
  flake.modules.darwin.macos =
    { lib, pkgs, ... }:
    let
      obsbot-center = pkgs.callPackage ./_obsbot-center/package.nix { };
    in
    {
      system.activationScripts.postActivation.text =
        lib.mkAfter # sh
          ''
            obsbot_pkg="${obsbot-center}"
            obsbot_marker="/var/lib/nix-darwin/obsbot-center-pkg"
            if [ "$(cat "$obsbot_marker" 2>/dev/null)" != "$obsbot_pkg" ]; then
              echo "📷 Installing /Applications/OBSBOT_Center.app"
              rm -rf /Applications/OBSBOT_Center.app
              /usr/bin/ditto "$obsbot_pkg/Applications/OBSBOT_Center.app" /Applications/OBSBOT_Center.app
              mkdir -p "$(dirname "$obsbot_marker")"
              echo "$obsbot_pkg" > "$obsbot_marker"
            fi
          '';
    };
}
