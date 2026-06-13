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
              cfg = pkgs.writeText "firefox-favicons.cfg" (builtins.readFile ../../_lib/firefox/firefox.cfg);
              icons = pkgs.writeText "favicon-icons.js" (builtins.readFile ../../_lib/firefox/favicon-icons.js);
              # Linux-only prefs (UI scaling). Materialized like cfg so the build
              # sandbox reads content at eval rather than a dirty-checkout subpath.
              prefs = pkgs.writeText "firefox-linux-prefs.js" (builtins.readFile ./prefs.js);
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
          ];
        };

        # Drop userChrome.css + user.js into each Firefox profile: the dark-favicon
        # inversion (tagged by firefox.cfg) and enlarged tab icons live in CSS.
        # Mirrors the macOS module — profiles get random IDs, so glob whatever
        # exists. userChrome.css is a live symlink (edits apply on next restart);
        # user.js is the shared prefs concatenated with the Linux-only VA-API
        # hardware-decode prefs (vaapi.js), which must be user_prefs applied
        # early — see vaapi.js. Both sources are read at activation, so edits
        # apply on the next `just`/switch then a Firefox restart.
        home.activation.firefox-userchrome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          profilesRoot="$HOME/.mozilla/firefox"
          [ -d "$profilesRoot" ] || exit 0

          for profile in "$profilesRoot"/*/; do
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
            "image/*" = browser;
            "text/html" = router;
            "text/plain" = browser;
            "x-scheme-handler/ftp" = browser;
            "x-scheme-handler/http" = router;
            "x-scheme-handler/https" = router;
          };
      };
    };
}
