{
  flake.modules.homeManager.darwin =
    { config, lib, ... }:
    let
      ffDir = "Library/Application Support/Firefox";
      # Platform-agnostic assets (firefox.cfg, favicon-icons.js, userChrome.css,
      # user.js) live in the shared dir; autoconfig.js below is macOS-specific.
      shared = "${config.dotFilesDir}/modules/_lib/firefox";
      src = "${config.dotFilesDir}/modules/home-darwin/firefox";
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
            ln -sfn "${shared}/userChrome.css" "$profile/chrome/userChrome.css"
            ln -sfn "${shared}/user.js"         "$profile/user.js"
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
          ln -sfn "${shared}/firefox.cfg"      "$res/firefox.cfg"
          ln -sfn "${shared}/favicon-icons.js" "$res/favicon-icons.js"
          ln -sfn "${src}/autoconfig.js"       "$res/defaults/pref/autoconfig.js"
        '';
      };
    };
}
