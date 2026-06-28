{
  flake.modules.homeManager.darwin =
    {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }:
    let
      ffDir = "Library/Application Support/Firefox";
      # PiP mover, authored in TypeScript and bundled to a chrome subscript
      # (packages/firefox-pip-mover). firefox.cfg loadSubScript's it at startup.
      pipMover = "${pkgs.pkgs-mine.firefox-pip-mover}/pip-mover.js";
      # Platform-agnostic assets (firefox.cfg, favicon-icons.js, userChrome.css,
      # user.js) live in the shared dir; autoconfig.js below is macOS-specific.
      shared = "${config.dotFilesDir}/modules/_lib/firefox";
      src = "${config.dotFilesDir}/modules/home-darwin/firefox";

      # The bundle path + coarse signing-identity matcher are declared once in
      # security.tcc (which also pins the matching csreq from the bundle's DR). We
      # read them back here so the re-sign and the grant can't drift. The exact cert
      # is resolved from the login keychain at activation (below), so cert rotation
      # needs no config change. Empty resignIdentity ⇒ no re-sign (non-nox hosts).
      ffTcc = lib.findFirst (a: a.bundleId == "org.mozilla.firefox") {
        appPath = "/Applications/Firefox.app";
        resignIdentity = "";
      } (osConfig.security.tcc.apps or [ ]);
      ffApp = ffTcc.appPath;
      inherit (ffTcc) resignIdentity;
    in
    {
      config = {
        # Firefox creates profile dirs with random IDs (e.g. j7ttlvnx.default-release)
        # so we can't hardcode a path. This activation script discovers every
        # profile present on the machine and drops symlinks into each:
        #   <profile>/user.js                — enables legacy stylesheets
        #   <profile>/chrome/userChrome.css  — style overrides (incl. the macOS
        #     fullscreen notch inset)
        # Both are mkOutOfStoreSymlink-equivalent: pointing at the live dots repo
        # so edits show up after a Firefox restart with no rebuild needed.
        # NB: userContent.css does NOT load in this build — the fullscreen fix is in
        # userChrome.css instead.
        home.activation.firefox-userchrome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          profilesRoot="$HOME/${ffDir}/Profiles"
          [ -d "$profilesRoot" ] || exit 0

          for profile in "$profilesRoot"/*/; do
            [ -d "$profile" ] || continue
            mkdir -p "$profile/chrome"
            ln -sfn "${shared}/userChrome.css" "$profile/chrome/userChrome.css"
            ln -sfn "${shared}/user.js"         "$profile/user.js"
            # Drop the dead userContent.css symlink from earlier attempts.
            rm -f "$profile/chrome/userContent.css"
          done
        '';

        # Inject a Firefox autoconfig script into the app bundle (PDF tab favicons).
        # autoconfig can only be bootstrapped from the app's defaults/pref dir — there
        # is no profile-based entrypoint — so these symlinks land inside Firefox.app.
        # Note: a Homebrew cask upgrade replaces the bundle and wipes them; re-running
        # `just system` restores them.
        #
        # Injecting these files breaks Firefox's Apple code seal. Under
        # amfi_get_out_of_my_way=1 that makes tccd treat Firefox as an unsigned
        # platform binary and deny camera/mic/screen-capture. We repair it by
        # re-signing with an Apple-anchored cert (ad-hoc does NOT work — still
        # platform-flagged). The exact identity is resolved at activation from the
        # login keychain by matching ${resignIdentity}, so a rotated/renewed cert
        # just works. This runs as the user so codesign can reach the signing key
        # (the first run may prompt — choose "Always Allow"). Guarded on --verify so
        # we only re-sign when the seal is actually broken (e.g. after a Firefox
        # self-update / cask upgrade). security.tcc then pins the bundle's resulting
        # designated requirement as the csreq.
        home.activation.firefox-autoconfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          res="${ffApp}/Contents/Resources"
          [ -d "$res" ] || exit 0
          mkdir -p "$res/defaults/pref"
          ln -sfn "${shared}/firefox.cfg"      "$res/firefox.cfg"
          ln -sfn "${shared}/favicon-icons.js" "$res/favicon-icons.js"
          ln -sfn "${pipMover}"                "$res/pip-mover.js"
          ln -sfn "${src}/autoconfig.js"       "$res/defaults/pref/autoconfig.js"
          ${lib.optionalString (resignIdentity != "") ''
            if ! /usr/bin/codesign --verify "${ffApp}" >/dev/null 2>&1; then
              identity=$(/usr/bin/security find-identity -v -p codesigning \
                | grep -F ${lib.escapeShellArg resignIdentity} | head -1 \
                | sed -E 's/.*"(.*)".*/\1/')
              if [ -n "$identity" ]; then
                /usr/bin/codesign --force --sign "$identity" \
                  --preserve-metadata=entitlements "${ffApp}" || true
              else
                echo "firefox-autoconfig: no codesigning identity matching '${resignIdentity}'; skipping re-sign" >&2
              fi
            fi
          ''}
        '';
      };
    };
}
