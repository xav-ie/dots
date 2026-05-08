# dyld-inject: shared coordinator for system-wide DYLD_INSERT_LIBRARIES
# injection, plus the macOS Tahoe window mods that depend on it.
#
# There's exactly one DYLD_INSERT_LIBRARIES environment variable per
# launchd domain, so multiple modules that want to inject dylibs into
# every GUI process can't each own their own launchd agent — they'd
# fight over the value. This module solves that by exposing a single
# list option (`services.dyldInject.libraries`) that other modules
# append their dylib paths to. A single launchd agent runs
# `launchctl setenv DYLD_INSERT_LIBRARIES <colon-joined>` at login, so
# dyld pulls each contributed dylib into every launchd-spawned GUI
# process (Finder, Dock, Safari, Firefox, every daemon, etc.).
#
# Sub-modules that depend on this mechanism live alongside as nested
# imports, all enabled by default and contributing one dylib each:
#   • ./square-corners        — kill rounded corners (NSThemeFrame
#                               swizzles + system Aqua.car patch).
#                               See its default.nix for full docs.
#   • ./remove-window-rim     — kill the 1px Liquid-Glass border
#                               (NSWindow shadowParameters swizzle).
#                               See its default.nix for full docs.
#   • ./pin-iphone-mirroring  — pin iPhone Mirroring's window to
#                               NSFloatingWindowLevel so it stays on
#                               top. See its default.nix for full
#                               docs.
#
# Required system state (set elsewhere, this module assumes it):
#   • amfi_get_out_of_my_way=1 in nvram boot-args (../boot-args.nix)
#     — without this, dyld silently strips DYLD_INSERT_LIBRARIES from
#     hardened-runtime apps, so contributed dylibs would never load
#     into Safari / FaceTime / etc.
#   • SIP disabled (Recovery: csrutil disable) — required by AMFI to
#     accept the boot-arg in the first place.
#
# Usage from another module:
#
#   services.dyldInject.libraries = lib.mkIf cfg.enable [
#     "''${myDylibPackage}/lib/Foo.dylib"
#   ];
#
# That's it — list options merge across modules, so multiple
# contributors compose without coordination.
#
# Caveat: setting `libraries = []` removes the launchd agent on next
# activation, but the env var the previous agent already set lives in
# the launchd session until logout. If you disable everything
# mid-session and want it to take effect immediately, run
# `launchctl unsetenv DYLD_INSERT_LIBRARIES` and relaunch any AppKit
# apps you want unmodified. A reboot/logout clears it cleanly.
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.dyldInject;
in
{
  imports = [
    ./square-corners
    ./remove-window-rim
    ./pin-iphone-mirroring
  ];

  options.services.dyldInject = {
    libraries = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = lib.literalExpression ''
        [ "''${pkgs.my-dylib}/lib/MyDylib.dylib" ]
      '';
      description = ''
        Dylibs to inject system-wide via DYLD_INSERT_LIBRARIES. Modules
        append to this list rather than managing their own launchd
        agents; a single agent owned by this module collects everything
        and sets the env var once at login.
      '';
    };
  };

  config = lib.mkIf (cfg.libraries != [ ]) {
    home-manager.users.${config.defaultUser}.launchd.agents.dyld-inject = {
      enable = true;
      config = {
        ProgramArguments = [
          "/bin/launchctl"
          "setenv"
          "DYLD_INSERT_LIBRARIES"
          (lib.concatStringsSep ":" cfg.libraries)
        ];
        RunAtLoad = true;
      };
    };
  };
}
