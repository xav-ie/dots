{
  flake.modules.homeManager.darwin =
    { pkgs, lib, ... }:
    let
      name = "firefox-router";
      id = "casa.lalala.${name}";
    in
    {
      # macOS link router: FirefoxRouter.app (packages/firefox-router-app)
      # registers as a browser and forwards clicked URLs to firefox-router, which
      # resolves Work vs Personal and execs Firefox directly. This mirrors the
      # Linux .desktop handler.
      #
      # Installed as a real copy rather than a store symlink so LaunchServices
      # registers a stable bundle, then ad-hoc signed so the copied Info.plist is
      # sealed into its signature.
      #
      # LSUIElement keeps the app a background agent: links are forwarded
      # silently with no Dock bounce or focus steal. The side effect is that the
      # System Settings "Default web browser" dropdown hides background apps, so we
      # never use that dropdown — the firefox-router-default activation below sets
      # the default handler programmatically instead.
      config.home.activation."${name}-app" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        app="$HOME/Applications/FirefoxRouter.app"
        lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

        mkdir -p "$HOME/Applications"
        rm -rf "$app"
        cp -R ${pkgs.pkgs-mine.firefox-router-app}/Applications/FirefoxRouter.app "$app"
        chmod -R u+w "$app"
        /usr/bin/codesign --force --sign - "$app"

        [ -x "$lsregister" ] && "$lsregister" -f "$app" || true
      '';

      # Make FirefoxRouter the default http/https handler. macOS deliberately gates
      # default-*browser* changes behind a secure GUI confirmation: a programmatic
      # set returns success but defers the change until the user clicks "Use
      # FirefoxRouter" once. We only invoke the setter when it isn't already the
      # default, so after that one confirmation every later rebuild is a silent
      # no-op (no prompt, no change). JXA via /usr/bin/osascript needs no compiler,
      # SDK, or Xcode license.
      config.home.activation."${name}-default" = lib.hm.dag.entryAfter [ "${name}-app" ] ''
        /usr/bin/osascript -l JavaScript ${./set-default-browser.js} ${id} \
          || echo "${name}-default: failed to set default browser" >&2
      '';
    };
}
