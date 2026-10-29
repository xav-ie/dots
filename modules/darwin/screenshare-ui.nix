# screenshare-ui (inputs.screenshare-ui): macOS UI that leaks into screen
# shares, redrawn in panels hidden from capture — the ⌘-Tab switcher, a
# stand-in Dock, and Mission Control / Dock / App Exposé hover UI — plus
# Screenshare Mode (hide every app from capture for a meeting; the sketchybar
# `hidewin` item shows it and opens its panel with `screenshare-ui panel`).
# Dock's own windows ignore NSWindowSharingNone, so its Dock-side hooks (a dylib
# injected into Dock through the shared services.dyldInject list; it does
# nothing in any other process) stop Dock drawing those and report them, keep
# the real Dock bar off screen while the stand-in is up, and in Screenshare Mode
# blank the Spaces bar's window miniatures. The per-app hiding library is
# injected by ./_dyld-inject/hide-windows.
#
# The switcher's event tap needs Accessibility. The bundle is ad-hoc signed as
# com.x.screenshare-ui at build time, so the grant pins the store bundle's
# cdhash and the agent runs that same bundle.
{
  flake.modules.darwin.macos =
    { pkgs, ... }:
    let
      app = pkgs.pkgs-mine.screenshare-ui;
      hooks = pkgs.pkgs-mine.screenshare-ui-dock-hooks;
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
