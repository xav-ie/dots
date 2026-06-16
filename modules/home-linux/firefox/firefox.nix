{
  flake.modules.homeManager.linux =
    {
      config,
      lib,
      pkgs,
      inputs,
      ...
    }:
    let
      # Platform-agnostic Firefox assets shared with the macOS module.
      shared = "${config.dotFilesDir}/modules/_lib/firefox";
    in
    {
      # Native-messaging bridge so the virtual headset's mute syncs with the
      # Zoom/Meet *web* apps (Firefox has no WebHID). Registers the
      # virtual_headset_bridge native host and force-installs the Mozilla-signed
      # extension from its latest GitHub release (installExtension), which
      # auto-updates via the manifest's update_url.
      # See github:xav-ie/virtual-headset extension/.
      imports = [ inputs.virtual-headset.homeManagerModules.firefox ];

      config = {
        programs.virtual-headset-firefox.enable = true;
        programs.virtual-headset-firefox.installExtension = true;

        home.packages = [ pkgs.firefoxpwa ];
        programs.firefox = {
          enable = true;
          # The PDF/JSON/dark-favicon autoconfig script (see home-manager/firefox).
          # macOS symlinks these live into the mutable .app bundle; on Nix Linux
          # Firefox is read-only in the store, so they're baked into the package —
          # editing firefox.cfg or favicon-icons.js needs a `just system` rebuild.
          package =
            let
              # Materialize the assets as standalone store paths (content read at
              # eval) rather than referencing them as subpaths of the flake tree,
              # which the build sandbox can't reliably read from a dirty checkout.
              cfg = pkgs.writeText "firefox-favicons.cfg" (../../_lib/firefox/firefox.cfg |> builtins.readFile);
              icons = pkgs.writeText "favicon-icons.js" (
                ../../_lib/firefox/favicon-icons.js |> builtins.readFile
              );
              # Linux-only prefs (UI scaling). Materialized like cfg so the build
              # sandbox reads content at eval rather than a dirty-checkout subpath.
              prefs = pkgs.writeText "firefox-linux-prefs.js" (./prefs.js |> builtins.readFile);
            in
            (pkgs.pkgs-bleeding.firefox.override {
              # Appended (cat'd, no shell expansion) to the wrapper's mozilla.cfg.
              extraPrefsFiles = [
                cfg
                prefs
              ];
            }).overrideAttrs
              (old: {
                buildCommand =
                  old.buildCommand
                  # sh
                  + ''
                    libDir="$out/lib/firefox"
                    # The wrapper's autoconfig.js leaves the JS sandbox on, which hides
                    # Components/Services. firefox.cfg needs chrome privileges to call
                    # gBrowser.setIcon, so disable the sandbox for it.
                    echo 'pref("general.config.sandbox_enabled", false);' \
                      >> "$libDir/defaults/pref/autoconfig.js"
                    # firefox.cfg loads this sibling via Services.dirsvc.get("GreD").
                    cp ${icons} "$libDir/favicon-icons.js"
                  '';
              });
          nativeMessagingHosts = [ pkgs.firefoxpwa ];
        };
        home.sessionVariables = {
          # Route $BROWSER-driven openers through the profile router too.
          BROWSER = "firefox-router";
        };

        # Per-profile link router: https://github.com/outsmartly/* (and the rest of
        # the Outsmartly footprint) open in the Work profile, everything else in
        # Personal. Rules live in packages/firefox-router/rules.nix. This .desktop
        # is the default http/https/html handler; it forwards the URL to the
        # firefox-router binary, which resolves the target profile and launches it.
        xdg.desktopEntries.firefox-router = {
          name = "Firefox (profile router)";
          genericName = "Web Browser";
          exec = "firefox-router %U";
          terminal = false;
          type = "Application";
          noDisplay = true;
          mimeType = [
            "text/html"
            "x-scheme-handler/http"
            "x-scheme-handler/https"
            "image/png"
            "image/jpeg"
            "image/gif"
            "image/webp"
            "image/avif"
            "image/svg+xml"
            "image/bmp"
            "image/tiff"
          ];
        };

        # Drop userChrome.css + user.js into each Firefox profile: the dark-favicon
        # inversion (tagged by firefox.cfg) and enlarged tab icons live in CSS.
        # New-style (SelectableProfiles) profiles live in the Profile Groups DB,
        # not profiles.ini — and the firefox dir is full of stale profile dirs +
        # non-profile dirs (Crash Reports, Pending Pings, …), so neither a glob
        # nor profiles.ini identifies the real ones. Read `path` from the group
        # DB, exactly like firefox-router (packages/firefox-router): the most
        # recently modified Profile Groups/*.sqlite. userChrome.css is a live
        # symlink (edits apply on next restart); user.js is the shared prefs
        # concatenated with the Linux-only VA-API hardware-decode prefs
        # (vaapi.js), which must be user_prefs applied early — see vaapi.js.
        home.activation.firefox-userchrome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          profilesRoot="$HOME/.mozilla/firefox"
          db=$(ls -t "$profilesRoot/Profile Groups/"*.sqlite 2>/dev/null | head -1)
          [ -n "$db" ] || exit 0

          # `path` is absolute (IsRelative=0) or relative to the firefox dir.
          ${pkgs.sqlite}/bin/sqlite3 "file:$db?mode=ro&immutable=1" \
            "SELECT path FROM Profiles;" | while IFS= read -r path; do
            case "$path" in
              /*) profile="$path" ;;
              *) profile="$profilesRoot/$path" ;;
            esac
            [ -d "$profile" ] || continue
            mkdir -p "$profile/chrome"
            ln -sfn "${shared}/userChrome.css" "$profile/chrome/userChrome.css"
            # rm first: a leftover symlink from prior activations would make the
            # redirect below write through it into the repo's shared user.js.
            rm -f "$profile/user.js"
            cat "${shared}/user.js" "${config.dotFilesDir}/modules/home-linux/firefox/vaapi.js" \
              > "$profile/user.js"
          done
        '';

        xdg.mimeApps.defaultApplications =
          let
            browser = "firefox.desktop";
            # Navigable web links go through the profile router; everything else
            # (local files, images, ftp) opens Firefox directly.
            router = "firefox-router.desktop";
          in
          {
            "application/xhtml+xml" = browser;
            "application/xml" = browser;
            # Open images via the profile router (firefox renders them; the
            # router resolves a default profile and, with its bare-path->file://
            # normalization, opens local files). NOTE: xdg mimeApps keys must be
            # explicit MIME types — an "image/*" glob is silently ignored, which
            # is why image/png previously fell through to chromium.
            "image/png" = router;
            "image/jpeg" = router;
            "image/gif" = router;
            "image/webp" = router;
            "image/avif" = router;
            "image/svg+xml" = router;
            "image/bmp" = router;
            "image/tiff" = router;
            "text/html" = router;
            "text/plain" = browser;
            "x-scheme-handler/ftp" = browser;
            "x-scheme-handler/http" = router;
            "x-scheme-handler/https" = router;
          };
      };
    };
}
