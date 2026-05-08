# pin-iphone-mirroring: keep macOS iPhone Mirroring's window above
# normal app windows.
#
# iPhone Mirroring (com.apple.ScreenContinuity) presents its window at
# the default NSNormalWindowLevel (= 0), so any other app window that
# becomes key sits on top of it. This module injects a tiny dylib
# that, only inside iPhone Mirroring's process, lifts the window to
# NSFloatingWindowLevel (= 3) — above normal app windows but below
# menus and status items.
#
# Implementation (./pkgs/pin-iphone-mirroring): bundle-id-gated dylib
# that swizzles -[NSWindow setLevel:] to clamp below-floating up to
# floating, then on NSApplicationDidFinishLaunchingNotification walks
# every existing window and bumps it. See IPhoneMirroringPin.m for the
# full design.
#
# The dylib is loaded into every launchd-spawned GUI process via
# services.dyldInject.libraries (it has to be — there's no per-process
# DYLD_INSERT_LIBRARIES), but its constructor returns immediately for
# any bundle id other than com.apple.ScreenContinuity.
#
# Enabled by default. To opt out:
#   services.dyldInject.pinIPhoneMirroring.enable = false;
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dyldInject.pinIPhoneMirroring;
  pin-iphone-mirroring = pkgs.callPackage ./pkgs/pin-iphone-mirroring { };
in
{
  options.services.dyldInject.pinIPhoneMirroring = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Inject a dylib that pins macOS iPhone Mirroring's window to
        NSFloatingWindowLevel so it stays above normal app windows.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.dyldInject.libraries = [
      "${pin-iphone-mirroring}/lib/IPhoneMirroringPin.dylib"
    ];
  };
}
