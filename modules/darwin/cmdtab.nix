# cmdtab (~/Projects/cmdtab): a ⌘-Tab switcher clone whose panel is hidden from
# screen capture — the native switcher is drawn by Dock, whose windows ignore
# NSWindowSharingNone, so it leaks every running app into a screenshare. cmdtab
# turns the native hotkeys off while it runs and restores them on exit.
#
# Its event tap needs Accessibility. The bundle is ad-hoc signed as com.x.cmdtab
# at build time, so the grant pins the store bundle's cdhash and the agent runs
# that same bundle. Per-process runtime icons (each Firefox profile's badge) are
# published by the hide-windows dylib; see ./_dyld-inject/hide-windows.
{
  flake.modules.darwin.macos =
    { inputs, pkgs, ... }:
    let
      cmdtab = inputs.cmdtab.packages.${pkgs.stdenv.hostPlatform.system}.default;
    in
    {
      # CMDTAB_PKG flips the launchd config hash so it restarts when the app's
      # code changes.
      launchd.user.agents.cmdtab.serviceConfig = {
        ProgramArguments = [ "${cmdtab}/Applications/cmdtab.app/Contents/MacOS/cmdtab" ];
        RunAtLoad = true;
        KeepAlive = true;
        EnvironmentVariables.CMDTAB_PKG = "${cmdtab}";
        StandardOutPath = "/tmp/cmdtab.out.log";
        StandardErrorPath = "/tmp/cmdtab.err.log";
      };

      security.tcc.apps = [
        {
          bundleId = "com.x.cmdtab";
          appPath = "${cmdtab}/Applications/cmdtab.app";
          pin = "cdhash";
          # pin = "cdhash" grants are written before launchd relaunches the
          # agent, so a rebuilt cmdtab starts with its grant already in place.
          services = [ "Accessibility" ];
        }
      ];
    };
}
