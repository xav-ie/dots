# hidewin-bar: run the menubar manager for the hide-windows agent as a
# login launchd agent. It needs no entitlements/TCC (NSWorkspace +
# distributed notifications only), so it runs straight from the store
# .app — no re-sign/install dance. HIDEWIN_BAR_PKG flips the launchd
# config hash so it restarts when the app's code changes.
_: {
  flake.modules.darwin.macos =
    { pkgs, ... }:
    {
      launchd.user.agents.hidewin-bar.serviceConfig = {
        ProgramArguments = [
          "${pkgs.pkgs-mine.hidewin-bar}/Applications/hidewin-bar.app/Contents/MacOS/hidewin-bar"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        EnvironmentVariables.HIDEWIN_BAR_PKG = "${pkgs.pkgs-mine.hidewin-bar}";
        StandardOutPath = "/tmp/hidewin-bar.out.log";
        StandardErrorPath = "/tmp/hidewin-bar.err.log";
      };
    };
}
