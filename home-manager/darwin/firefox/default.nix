{ config, lib, ... }:
let
  ffDir = "Library/Application Support/Firefox";
  src = "${config.dotFilesDir}/home-manager/darwin/firefox";
in
{
  config = {
    # Firefox creates profile dirs with random IDs (e.g. j7ttlvnx.default-release)
    # so we can't hardcode a path. This activation script discovers every
    # profile present on the machine and drops symlinks into each:
    #   <profile>/user.js                — enables legacy stylesheets
    #   <profile>/chrome/userChrome.css  — the actual style overrides
    # Both are mkOutOfStoreSymlink-equivalent: pointing at the live dots repo
    # so edits show up after a Firefox restart with no rebuild needed.
    home.activation.firefox-userchrome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      profilesRoot="$HOME/${ffDir}/Profiles"
      [ -d "$profilesRoot" ] || exit 0

      for profile in "$profilesRoot"/*/; do
        [ -d "$profile" ] || continue
        mkdir -p "$profile/chrome"
        ln -sfn "${src}/userChrome.css" "$profile/chrome/userChrome.css"
        ln -sfn "${src}/user.js"         "$profile/user.js"
      done
    '';

    # Inject a Firefox autoconfig script into the app bundle (PDF tab favicons).
    # autoconfig can only be bootstrapped from the app's defaults/pref dir — there
    # is no profile-based entrypoint — so these symlinks land inside Firefox.app.
    # Note: a Homebrew cask upgrade replaces the bundle and wipes them; re-running
    # `just system` restores them.
    home.activation.firefox-autoconfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      res="/Applications/Firefox.app/Contents/Resources"
      [ -d "$res" ] || exit 0
      mkdir -p "$res/defaults/pref"
      ln -sfn "${src}/firefox.cfg"      "$res/firefox.cfg"
      ln -sfn "${src}/favicon-icons.js" "$res/favicon-icons.js"
      ln -sfn "${src}/autoconfig.js"    "$res/defaults/pref/autoconfig.js"
    '';
  };
}
