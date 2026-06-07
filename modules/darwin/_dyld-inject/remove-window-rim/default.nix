# remove-window-rim: kill macOS Tahoe's 1px Liquid-Glass window border
# (a.k.a. "rim").
#
# Tahoe paints a 1px rim around every window via per-window shadow
# parameters. AppKit reads keys from the dictionary returned by
# `-[NSWindow shadowParameters]` (`com.apple.WindowShadowRimRadiusActive`,
# `WindowShadowRimDensityActive`, plus Inactive variants and InnerRim*
# counterparts) and pushes the values to WindowServer via CGS. With them
# zeroed, no rim is drawn.
#
# Implementation: a small dylib (./pkgs/remove-window-rim) injected into
# every launchd-spawned GUI process via the shared
# `services.dyldInject.libraries` list (../default.nix). The dylib's
# constructor swizzles `-[NSWindow shadowParameters]` so the keys come
# back as zero before AppKit reads them. Because *every* AppKit process
# answers from its own swizzled getter, Dock restarts (which re-push
# shadow params in long-lived processes) don't reintroduce the rim.
#
# Required system state (set elsewhere — this module assumes it):
#   • SIP disabled                (Recovery: csrutil disable)
#   • amfi_get_out_of_my_way=1 in nvram boot-args (../../boot-args.nix)
#     — without this, dyld silently strips DYLD_INSERT_LIBRARIES from
#     hardened-runtime apps like Safari, so the dylib never loads.
#
# Independent of `services.dyldInject.squareCorners` (which handles
# corner *radius* + system .car patching). You can enable either or
# both.
#
# Enabled by default. To opt out:
#   services.dyldInject.removeWindowRim.enable = false;
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dyldInject.removeWindowRim;
  remove-window-rim = pkgs.callPackage ./pkgs/remove-window-rim { };
in
{
  options.services.dyldInject.removeWindowRim = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Inject a dylib into every GUI process that zeros the rim keys
        in `-[NSWindow shadowParameters]`, suppressing Tahoe's 1px
        Liquid-Glass window border.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.dyldInject.libraries = [
      "${remove-window-rim}/lib/RemoveWindowRim.dylib"
    ];
  };
}
