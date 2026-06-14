# dyld-inject: shared coordinator for system-wide DYLD_INSERT_LIBRARIES
# injection, plus the macOS Tahoe window mods that depend on it.
#
# There's exactly one DYLD_INSERT_LIBRARIES environment variable per
# launchd domain, so multiple modules that want to inject dylibs into
# every GUI process can't each own their own launchd agent — they'd
# fight over the value. This module solves that by exposing a single
# list option (`services.dyldInject.libraries`) that other modules
# append their dylib paths to.
#
# Two layers keep the value in sync:
#
#   1. Launchd agent (RunAtLoad). On every login, the agent runs
#      `launchctl setenv DYLD_INSERT_LIBRARIES <colon-joined>` so dyld
#      pulls each contributed dylib into every launchd-spawned GUI
#      process (Finder, Dock, Safari, Firefox, every daemon, etc.).
#
#   2. postActivation script. The agent alone isn't sufficient because:
#      (a) home-manager rewrites the agent plist on activation but
#          doesn't bootout+bootstrap, so launchd keeps using the
#          previously-cached args; (b) even when an agent is freshly
#          re-bootstrapped mid-session, `launchctl setenv` invoked from
#          inside an agent process only updates the agent's sub-domain
#          and doesn't propagate to the parent gui/UID domain (this
#          only works at login, where launchd is starting fresh).
#      So on every `darwin-rebuild activate`, this module re-applies
#      the env from root via `sudo -u <defaultUser> launchctl setenv`,
#      which DOES propagate. After `just system` the runtime env is
#      always in sync with the configured libraries.
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
# `dyld-check` is installed unconditionally; run it any time to verify
# the runtime DYLD_INSERT_LIBRARIES matches the configured value, scan
# for crashes since the last rebuild, and surface dyld/AMFI errors.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dyldInject;
  # `writeNuApplication` comes from overlays/default.nix and is
  # auto-resolved by callPackage from pkgs.
  dyld-check = pkgs.callPackage ./pkgs/dyld-check { };
  joined = cfg.libraries |> lib.concatStringsSep ":";
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
        and sets the env var once at login, and a postActivation script
        re-applies it on every `darwin-rebuild activate`.
      '';
    };
  };

  config = lib.mkMerge [
    # `dyld-check` diagnostic CLI is always installed — it's useful
    # even when no libraries are configured (to confirm the empty
    # state) or when the agent didn't take effect for some reason.
    { environment.systemPackages = [ dyld-check ]; }

    (lib.mkIf (cfg.libraries != [ ]) {
      home-manager.users.${config.defaultUser}.launchd.agents.dyld-inject = {
        enable = true;
        config = {
          ProgramArguments = [
            "/bin/launchctl"
            "setenv"
            "DYLD_INSERT_LIBRARIES"
            joined
          ];
          RunAtLoad = true;
        };
      };

      # Apply the env right now (as the user, so it lands in gui/UID)
      # without waiting for the next login. See the long comment at
      # the top of this file for why this is necessary.
      system.activationScripts.postActivation.text = lib.mkAfter ''
        echo "==> dyld-inject:"
        if sudo -u ${config.defaultUser} launchctl setenv DYLD_INSERT_LIBRARIES "${joined}" 2>/dev/null; then
          echo "    setenv DYLD_INSERT_LIBRARIES (${cfg.libraries |> lib.length |> toString} dylib(s))"
        else
          echo "    warning: setenv failed (no active GUI session for ${config.defaultUser}?)"
        fi
      '';
    })

    # When libraries become empty, clear the env on activation so the
    # value the previous agent set doesn't keep injecting.
    (lib.mkIf (cfg.libraries == [ ]) {
      system.activationScripts.postActivation.text = lib.mkAfter ''
        echo "==> dyld-inject: clearing DYLD_INSERT_LIBRARIES (no libraries configured)"
        sudo -u ${config.defaultUser} launchctl unsetenv DYLD_INSERT_LIBRARIES 2>/dev/null || true
      '';
    })
  ];
}
