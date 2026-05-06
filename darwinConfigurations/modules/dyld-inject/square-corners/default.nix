# square-corners: kill macOS Tahoe's rounded window corners.
#
# Tahoe rounds window corners through two unrelated pipelines, so we
# patch both:
#
#   1. Per-app dylib (./pkgs/macos-corner-fix)
#      A small dylib injected into every AppKit process via the shared
#      services.dyldInject.libraries mechanism (see ../default.nix).
#      It swizzles NSThemeFrame's `_cornerRadius` /
#      `_getCachedWindowCornerRadius` / `_topCornerSize` /
#      `_bottomCornerSize` to return the configured radius (default 0).
#      AppKit asks NSThemeFrame "what corner should I round to?" and
#      our swizzled getters answer 0.
#
#   2. System-wide .car patch (./pkgs/car-edit + ./pkgs/aqua-patcher)
#      Even with the dylib running, AppKit still asks WindowServer to
#      clip windows to a rounded shape using corner-mask images stored
#      in /System/…/Aqua.car (light) and DarkAqua.car (dark). The
#      `car-edit` Swift CLI rewrites the WindowShapeEdges renditions in
#      those files so the corner mask becomes a uniform rectangle —
#      WindowServer then clips windows to a hard rectangle. The
#      postActivation script below detects when the on-disk .car files
#      differ from the patched version we'd produce (this happens after
#      every macOS point update, which reseals the system snapshot back
#      to Apple's originals), then mounts the system volume read-write,
#      copies the patched files in, and creates a new bootable APFS
#      snapshot via `bless`.
#
# Note: window *border* (the 1px Liquid-Glass rim) is a separate
# concern handled by ../remove-window-rim/. You can enable square
# corners without removing the rim, or vice versa.
#
# Required system state (all set elsewhere — this module assumes them):
#   • SIP disabled                (Recovery: csrutil disable)
#   • Authenticated Root disabled (Recovery: csrutil authenticated-root disable)
#   • amfi_get_out_of_my_way=1 in nvram boot-args (set by ../../boot-args.nix)
#     — without this, dyld silently strips DYLD_INSERT_LIBRARIES from
#     hardened-runtime apps like Safari, so the dylib never loads.
#
# Helper CLI (./pkgs/aqua-patcher) for ad-hoc operations:
#   aqua-patcher status   — show SIP/auth-root state, current/backup md5s
#   aqua-patcher backup   — copy current system .car files to ~/Documents
#   aqua-patcher restore  — restore originals from backup, bless, reboot
#   aqua-patcher apply    — same install flow that activation runs
#
# Enabled by default. To opt out:
#   services.dyldInject.squareCorners.enable = false;
#
# After macOS updates you'll need to `sudo shutdown -r now` once activation
# reapplies the patch (it'll print "REBOOT to apply" when that happens).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dyldInject.squareCorners;

  # Match how packages/default.nix constructs writeNuApplication so the
  # nu-script wrapping is identical to the rest of the repo.
  writeNuApplication =
    inputs.nuenv.lib.mkNushellScriptApplication pkgs.nushell pkgs.writeTextFile
      pkgs.lib;

  car-edit = pkgs.callPackage ./pkgs/car-edit { };
  aqua-patcher = pkgs.callPackage ./pkgs/aqua-patcher { inherit car-edit writeNuApplication; };
  macos-corner-fix = pkgs.callPackage ./pkgs/macos-corner-fix {
    inherit (inputs) macos-corner-fix-src;
    inherit (cfg) cornerRadius;
  };

  carEditBin = "${car-edit}/bin/car-edit";
  targetsArg = lib.escapeShellArgs cfg.targets;
in
{
  options.services.dyldInject.squareCorners = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the macOS Tahoe square-corner mod (NSThemeFrame swizzles + Aqua.car patch).";
    };

    targets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "Aqua.car"
        "DarkAqua.car"
      ];
      description = ''
        Which appearance .car files to patch on every activation. Defaults to
        both light + dark for symmetric coverage. Drop one if you want it
        kept untouched as a recovery fallback (toggle System Settings →
        Appearance to switch into the unmodified theme).
      '';
    };

    cornerRadius = lib.mkOption {
      type = lib.types.str;
      default = "0.0";
      description = ''
        Corner radius the dylib forces NSThemeFrame to report. 0.0 = fully
        square. Useful values: 0.0, 4.0, 10.0 (Sequoia), 16.0 (Tahoe default).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      aqua-patcher
      car-edit
    ];

    # Contribute the corner-fix dylib to the shared injection list.
    # The single launchd agent owned by ../default.nix collects every
    # contributor and does one `launchctl setenv DYLD_INSERT_LIBRARIES`.
    services.dyldInject.libraries = [
      "${macos-corner-fix}/lib/SafariCornerTweak.dylib"
    ];

    # Runs as root every `darwin-rebuild activate`. Idempotent — if the
    # patched-from-current md5 equals the system md5, nothing happens. After
    # macOS point updates wipe the patched snapshot, the activation detects
    # the mismatch and reapplies on next `just system`.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      _squareCornersPatchCars() {
        echo "==> square-corners:"

        if ! csrutil status 2>&1 | grep -qi disabled; then
          echo "    skip: SIP enabled (boot Recovery, run: csrutil disable)"
          return 0
        fi
        if ! csrutil authenticated-root status 2>&1 | grep -qi disabled; then
          echo "    skip: Authenticated Root enabled (boot Recovery, run: csrutil authenticated-root disable)"
          return 0
        fi

        local STAGE=/var/aqua-patch/stage
        local MOUNT=/var/aqua-patch/mnt
        local SYS_DIR=/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources
        mkdir -p "$STAGE" "$MOUNT"

        local ROOT_DEVICE BASE_DISK
        ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')
        BASE_DISK=''${ROOT_DEVICE%s[0-9]*}

        local targets=(${targetsArg})

        local NEED_INSTALL=0
        for car in "''${targets[@]}"; do
          local src="$SYS_DIR/$car"
          local out="$STAGE/$car"
          if [ ! -f "$src" ]; then
            echo "    warning: $src not found, skipping"
            continue
          fi
          ${carEditBin} "$src" -o "$out" >/dev/null
          if [ "$(md5 -q "$src")" = "$(md5 -q "$out")" ]; then
            echo "    $car: already patched"
          else
            echo "    $car: needs patching"
            NEED_INSTALL=1
          fi
        done

        if [ "$NEED_INSTALL" -eq 0 ]; then
          return 0
        fi

        # Detect mount by content rather than `mount` output: if the system
        # tree is already visible through $MOUNT, we're good. Avoids
        # EINPROGRESS when a previous activation left the volume mounted.
        if [ ! -d "$MOUNT/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources" ]; then
          echo "    mounting $BASE_DISK at $MOUNT (RW)"
          mount -o nobrowse -t apfs "$BASE_DISK" "$MOUNT"
        fi

        for car in "''${targets[@]}"; do
          local out="$STAGE/$car"
          local target="$MOUNT/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources/$car"
          if [ -f "$out" ]; then
            cp "$out" "$target"
            echo "    installed: $car"
          fi
        done

        echo "    blessing modified snapshot"
        bless --mount "$MOUNT" --bootefi --create-snapshot
        echo "    square-corners: REBOOT to apply"
      }
      _squareCornersPatchCars
    '';
  };
}
