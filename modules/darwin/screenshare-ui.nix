# screenshare-ui (~/Projects/screenshare-ui): macOS UI that leaks into screen
# shares, redrawn in panels hidden from capture — the ⌘-Tab switcher, a
# stand-in Dock while hidewin's Screenshare Mode is on, and Mission Control /
# Dock / App Exposé hover UI. Dock's own windows ignore NSWindowSharingNone, so
# its Dock-side hooks (a dylib injected into Dock through the shared
# services.dyldInject list; it does nothing in any other process) stop Dock
# drawing those and report them, and in Screenshare Mode move the real Dock bar
# off screen and blank the Spaces bar's window miniatures.
#
# The switcher's event tap needs Accessibility. The bundle is ad-hoc signed as
# com.x.screenshare-ui at build time, so the grant pins the store bundle's
# cdhash and the agent runs that same bundle. Per-process runtime icons (each
# Firefox profile's badge) are published by the hide-windows dylib; see
# ./_dyld-inject/hide-windows.
{
  flake.modules.darwin.macos =
    { inputs, pkgs, ... }:
    let
      app = pkgs.callPackage "${inputs.screenshare-ui}/default.nix" { };
      hooks = pkgs.callPackage "${inputs.screenshare-ui}/dock-hooks.nix" { };
    in
    {
      # SCREENSHARE_UI_PKG flips the launchd config hash so it restarts when
      # the app's code changes.
      launchd.user.agents.screenshare-ui.serviceConfig = {
        ProgramArguments = [
          "${app}/Applications/screenshare-ui.app/Contents/MacOS/screenshare-ui"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        EnvironmentVariables.SCREENSHARE_UI_PKG = "${app}";
        StandardOutPath = "/tmp/screenshare-ui.out.log";
        StandardErrorPath = "/tmp/screenshare-ui.err.log";
      };

      services.dyldInject.libraries = [ "${hooks}/lib/ScreenshareUIDockHooks.dylib" ];

      security.tcc.apps = [
        {
          bundleId = "com.x.screenshare-ui";
          appPath = "${app}/Applications/screenshare-ui.app";
          pin = "cdhash";
          # pin = "cdhash" grants are written before launchd relaunches the
          # agent, so a rebuilt app starts with its grant already in place.
          services = [ "Accessibility" ];
        }
      ];
    };
}
