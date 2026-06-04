{ pkgs, lib, ... }:
let
  ffr = "${pkgs.pkgs-mine.firefox-router}/bin/firefox-router";
in
{
  # macOS link router: build a tiny AppleScript applet (FirefoxRouter.app) that
  # registers as a browser and forwards clicked URLs to firefox-router, which
  # resolves Work vs Personal and execs Firefox directly. This mirrors the
  # Linux .desktop handler. Built at activation (not in the Nix sandbox)
  # because osacompile is a macOS system tool — same pattern as the
  # firefox-autoconfig activation in this module.
  #
  # One-time manual step: System Settings -> Desktop & Dock -> Default web
  # browser -> FirefoxRouter (macOS disallows setting this silently).
  config.home.activation.firefox-router-app = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    app="$HOME/Applications/FirefoxRouter.app"
    plist="$app/Contents/Info.plist"
    plistbuddy="/usr/libexec/PlistBuddy"
    lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    tmp="$(mktemp -d)"
    src="$tmp/firefox-router.applescript"
    cat > "$src" <<APPLESCRIPT
    on open location this_URL
        do shell script "${ffr} " & quoted form of this_URL
    end open location

    on run
        do shell script "${ffr}"
    end run
    APPLESCRIPT

    mkdir -p "$HOME/Applications"
    rm -rf "$app"
    /usr/bin/osacompile -o "$app" "$src"
    rm -rf "$tmp"

    # Identify the bundle and declare it an http/https handler so macOS lists
    # it as a default-browser candidate. Newer osacompile output may omit
    # CFBundleIdentifier entirely, so Add it when Set can't find the key.
    $plistbuddy -c "Set :CFBundleIdentifier casa.lalala.firefox-router" "$plist" 2>/dev/null \
      || $plistbuddy -c "Add :CFBundleIdentifier string casa.lalala.firefox-router" "$plist"
    $plistbuddy -c "Add :LSUIElement bool true" "$plist" 2>/dev/null || true
    $plistbuddy -c "Add :CFBundleURLTypes array" "$plist" 2>/dev/null || true
    $plistbuddy -c "Add :CFBundleURLTypes:0 dict" "$plist" 2>/dev/null || true
    $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleURLName string casa.lalala.firefox-router" "$plist" 2>/dev/null || true
    $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleTypeRole string Viewer" "$plist" 2>/dev/null || true
    $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes array" "$plist" 2>/dev/null || true
    $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string http" "$plist" 2>/dev/null || true
    $plistbuddy -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:1 string https" "$plist" 2>/dev/null || true

    [ -x "$lsregister" ] && "$lsregister" -f "$app" || true
  '';
}
