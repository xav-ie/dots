{
  flake.modules.homeManager.darwin =
    { pkgs, lib, ... }:
    let
      name = "firefox-router";
      ffr = "${pkgs.pkgs-mine.${name}}/bin/${name}";
      id = "casa.lalala.${name}";
    in
    {
      # macOS link router: build a tiny AppleScript applet (FirefoxRouter.app) that
      # registers as a browser and forwards clicked URLs to firefox-router, which
      # resolves Work vs Personal and execs Firefox directly. This mirrors the
      # Linux .desktop handler. Built at activation (not in the Nix sandbox)
      # because osacompile is a macOS system tool — same pattern as the
      # firefox-autoconfig activation in this module.
      #
      # LSUIElement keeps the applet a background agent: links are forwarded
      # silently with no Dock bounce or focus steal. The side effect is that the
      # System Settings "Default web browser" dropdown hides background apps, so we
      # never use that dropdown — the firefox-router-default activation below sets
      # the default handler programmatically instead.
      config.home.activation."${name}-app" = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        app="$HOME/Applications/FirefoxRouter.app"
        plistbuddy="/usr/libexec/PlistBuddy"
        lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

        tmp="$(mktemp -d)"
        src="$tmp/${name}.applescript"
        cat > "$src" <<APPLESCRIPT
        on open location this_URL
            do shell script "${ffr} " & quoted form of this_URL
        end open location

        on run
            do shell script "${ffr}"
        end run
        APPLESCRIPT

        # Compile into the temp dir first: a fresh output path can't hit
        # osacompile's intermittent "duplicate filename (rename)" error the way
        # writing straight over the existing ~/Applications/FirefoxRouter.app can
        # (e.g. while Spotlight/LaunchServices is touching the folder). Configure
        # it there, then atomically swap it into place at the end.
        build="$tmp/FirefoxRouter.app"
        /usr/bin/osacompile -o "$build" "$src"
        plist="$build/Contents/Info.plist"

        # Identify the bundle and declare it an http/https handler so macOS lists
        # it as a default-browser candidate. Newer osacompile output may omit
        # CFBundleIdentifier entirely, so Add it when Set can't find the key.
        $plistbuddy -c "Set :CFBundleIdentifier ${id}" "$plist" 2>/dev/null \
          || $plistbuddy -c "Add :CFBundleIdentifier string ${id}" "$plist"
        $plistbuddy -c "Add :LSUIElement bool true" "$plist" 2>/dev/null || true
        $plistbuddy -c "Add :CFBundleURLTypes array" "$plist" 2>/dev/null || true
        $plistbuddy -c "Add :CFBundleURLTypes:0 dict" "$plist" 2>/dev/null || true
        $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string ${id}" "$plist" 2>/dev/null || true
        $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleTypeRole string Viewer" "$plist" 2>/dev/null || true
        $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$plist" 2>/dev/null || true
        $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string http" "$plist" 2>/dev/null || true
        $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:1 string https" "$plist" 2>/dev/null || true

        # Swap the fully-configured temp bundle into place atomically.
        mkdir -p "$HOME/Applications"
        rm -rf "$app"
        mv "$build" "$app"
        rm -rf "$tmp"

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
