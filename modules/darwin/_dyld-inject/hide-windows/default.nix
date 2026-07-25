# hide-windows: the macOS answer to Invisiwind. Windows are VISIBLE by
# default (so continuous recorders like Dayflow work); the hidewin menubar
# app's "Screenshare Mode" (packages/hidewin-bar) hides everything from
# capture for a meeting, and you reveal the apps you want to present.
#
# An NSWindow is excluded from window-level capture (ScreenCaptureKit,
# CGWindowListCreateImage, all browser getDisplayMedia sharing incl.
# Zoom-in-a-tab) when its sharingType is NSWindowSharingNone — but that
# flag only works when set by the process that OWNS the window. So this
# rides the shared services.dyldInject.libraries inject to run inside
# every GUI process and flips the flag from the inside. See
# ./pkgs/hide-windows/HideWindows.m for the mechanism and its ceiling
# (native Zoom's default display-buffer capture bypasses it; browser
# sharing honors it).
#
# The sharing flag is per-window, honored by ALL window-level capturers —
# there's no "hide from Meet but show to Dayflow" exception. That's why
# hiding is a mode you toggle for a meeting, not an always-on filter.
#
# Required system state (assumed, set elsewhere): SIP disabled +
# amfi_get_out_of_my_way=1 (../boot-args.nix) — without amfi off, dyld
# strips DYLD_INSERT_LIBRARIES from hardened-runtime apps and the dylib
# never loads.
#
# Enabled by default. To opt out:  services.dyldInject.hideWindows.enable = false;
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dyldInject.hideWindows;
  hide-windows = pkgs.callPackage ./pkgs/hide-windows { };
in
{
  options.services.dyldInject.hideWindows = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Inject a dylib into every GUI app that can flip its windows to
        NSWindowSharingNone (excluded from screen capture). Windows are
        visible by default; the hidewin menubar's Screenshare Mode hides
        them for a meeting, and you reveal apps to present.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.dyldInject.libraries = [
      "${hide-windows}/lib/HideWindows.dylib"
    ];
  };
}
