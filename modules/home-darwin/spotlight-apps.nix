# Make home-manager GUI apps findable in Spotlight, as normal apps.
#
# home-manager only *symlinks* apps into ~/Applications/Home Manager Apps, and
# macOS won't index a symlink-to-/nix/store as an app (verified: a symlink gets
# no kMDItemContentType at all). Nor do macOS *aliases* (mkalias) help — an
# alias file indexes as `com.apple.alias-file`, searchable only by its filename,
# so VS Code is findable by "visual studio code" but not "code", and it shows as
# an alias rather than an app.
#
# The only thing that indexes as a real `com.apple.application-bundle` — with
# the target's Info.plist metadata, so `Cmd+Space → "code"` works (VS Code's
# CFBundleName is "Code") — is a real copy. So we `ditto` each app into
# ~/Applications (top-level, alongside the OS's own app locations).
#
# Copies are guarded by a per-app marker recording the source /nix/store path,
# so a package only gets re-copied when it actually changes. Store apps are
# read-only, so copies are made writable to allow later replacement.
#
# nix-darwin does the alias version of this for *system* apps; there's no
# built-in for home-manager user apps, which is the gap this fills.
{
  flake.modules.homeManager.darwin =
    { pkgs, lib, ... }:
    let
      spotlight-apps = pkgs.writeShellApplication {
        name = "spotlight-apps";
        runtimeInputs = [ pkgs.coreutils ];
        text = # sh
          ''
            src="''${HOME}/Applications/Home Manager Apps"
            dst="''${HOME}/Applications"
            state="''${HOME}/.local/state/hm-spotlight-apps"

            [ -d "$src" ] || exit 0

            mkdir -p "$state"
            managed="|"

            for link in "$src"/*.app; do
              [ -e "$link" ] || continue
              name="$(basename "$link")"
              target="$(readlink -f "$link")"
              marker="$state/$name.source"
              managed="$managed$name|"

              # Skip when the existing copy already tracks the current store path.
              if [ -d "$dst/$name" ] && [ "$(cat "$marker" 2>/dev/null)" = "$target" ]; then
                continue
              fi

              [ -n "''${VERBOSE:-}" ] && echo "spotlightApps: copying $name"
              chmod -R u+w "$dst/$name" 2>/dev/null || true
              rm -rf "''${dst:?}/''${name:?}"
              /usr/bin/ditto "$target" "$dst/$name" || continue
              chmod -R u+w "$dst/$name" 2>/dev/null || true
              printf '%s' "$target" > "$marker"
              /usr/bin/mdimport "$dst/$name" 2>/dev/null || true
            done

            # Remove copies whose source app no longer exists.
            for marker in "$state"/*.source; do
              [ -e "$marker" ] || continue
              n="$(basename "$marker" .source)"
              case "$managed" in
                *"|$n|"*) ;;
                *)
                  chmod -R u+w "$dst/$n" 2>/dev/null || true
                  rm -rf "''${dst:?}/''${n:?}"
                  rm -f "$marker"
                  ;;
              esac
            done
          '';
      };
    in
    {
      home.activation.spotlightApps = lib.hm.dag.entryAfter [
        "writeBoundary"
      ] "${spotlight-apps}/bin/spotlight-apps";
    };
}
