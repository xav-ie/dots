{
  config,
  lib,
  pkgs,
  ...
}:
# let
#   merge = lib.foldr (a: b: a // b) { };
#   inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;
# in
let
  # Platform-agnostic Firefox assets shared with the macOS module.
  shared = "${config.dotFilesDir}/home-manager/firefox";
in
{
  config = {
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
          cfg = pkgs.writeText "firefox-favicons.cfg" (builtins.readFile ../../firefox/firefox.cfg);
          icons = pkgs.writeText "favicon-icons.js" (builtins.readFile ../../firefox/favicon-icons.js);
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
            buildCommand = old.buildCommand + ''
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
      # setting this prevents dynamic profile configuration...
      # We should make this so it generates a program that attempts to set
      # profile settings instead
      # profiles.x = {
      #   id = 0;
      #   isDefault = true;
      #   settings = merge [
      #     (import ./annoyances.nix)
      #     (import ./settings.nix { inherit fonts; })
      #   ];
      #   userChrome = # css
      #     ''
      #       /* ########  Sidetabs Styles  ######### */
      #
      #       /* ~~~~~~~~ Hidden elements styles ~~~~~~~~~ */
      #       #TabsToolbar {
      #       	display: none !important;
      #       }
      #       #titlebar {
      #       	display: none !important;
      #       }
      #       #sidebar-header {
      #       	display: none !important;
      #       }
      #       /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */
      #       * {
      #         font-family: ${fonts.name "sans"}, ${fonts.name "emoji"} !important;
      #       }
      #
      #       /* #################################### */
      #     '';
      #
      #   extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
      #     bitwarden
      #     ublock-origin
      #     vimium-c
      #     newtab-adapter
      #     videospeed
      #   ];
      # };
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
    # exists. These are live symlinks into the repo: edits apply on the next
    # Firefox restart, no rebuild needed.
    home.activation.firefox-userchrome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      profilesRoot="$HOME/.mozilla/firefox"
      [ -d "$profilesRoot" ] || exit 0

      for profile in "$profilesRoot"/*/; do
        [ -d "$profile" ] || continue
        mkdir -p "$profile/chrome"
        ln -sfn "${shared}/userChrome.css" "$profile/chrome/userChrome.css"
        ln -sfn "${shared}/user.js"         "$profile/user.js"
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
}
