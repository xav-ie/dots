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
#      those files so the rounding mask is gone — WindowServer then stops
#      clipping to a rounded shape and the dylib's zero radius wins.
#      (Through earlier Tahoe builds car-edit filled the mask to a uniform
#      semi-opaque rectangle per the upstream recipe; macOS 26.5.x began
#      *drawing* that fill as a bar across the window top, so we now clear
#      the mask to fully transparent instead — see kGA8FillAlpha in
#      car-edit's main.swift.)
#      The postActivation script patches from Apple's PRISTINE .car, taken
#      from the read-only `com.apple.os.update-*` APFS snapshot — NOT the
#      live file: car-edit re-encodes the masks, so re-patching a patched
#      file is not idempotent. It detects when the live .car differs from
#      patched-from-pristine (true after every macOS point update, which
#      reseals the snapshot to Apple's originals), mounts the system volume
#      read-write, copies the patched files in, and creates a new bootable
#      APFS snapshot via `bless`.
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

  # `writeNuApplication` comes from overlays/default.nix and is
  # auto-resolved by callPackage from pkgs.
  car-edit = pkgs.callPackage ./pkgs/car-edit { };
  aqua-patcher = pkgs.callPackage ./pkgs/aqua-patcher { inherit car-edit; };
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
        local PRISTINE=/var/aqua-patch/pristine
        local RES_REL=System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources
        local SYS_DIR=/$RES_REL
        mkdir -p "$STAGE" "$MOUNT" "$PRISTINE"

        local ROOT_DEVICE BASE_DISK
        ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')
        BASE_DISK=''${ROOT_DEVICE%s[0-9]*}

        # car-edit MUST read Apple's PRISTINE .car, never the live (possibly
        # already-patched) one. car-edit re-encodes the GA8 shape masks as
        # ARGB, so a second pass over a patched file treats those masks as rim
        # color and clears them — wiping the square-corner mask instead of
        # re-squaring it (not idempotent). Apple's originals survive in the
        # read-only OS-update APFS snapshot; mount it and patch from there.
        local UPDATE_SNAP SRC_DIR
        UPDATE_SNAP=$(/usr/sbin/diskutil apfs listSnapshots / 2>/dev/null \
          | grep -oE 'com\.apple\.os\.update-[0-9A-F]+' | head -1)
        if [ -n "$UPDATE_SNAP" ] && [ ! -d "$PRISTINE/$RES_REL" ]; then
          /sbin/mount_apfs -o ro -s "$UPDATE_SNAP" "$BASE_DISK" "$PRISTINE" 2>/dev/null || true
        fi
        if [ -d "$PRISTINE/$RES_REL" ]; then
          SRC_DIR="$PRISTINE/$RES_REL"
          echo "    source: pristine OS-update snapshot"
        else
          SRC_DIR="$SYS_DIR"
          echo "    warning: pristine snapshot unavailable; patching live system (may not be idempotent)"
        fi

        local targets=(${targetsArg})

        local NEED_INSTALL=0
        for car in "''${targets[@]}"; do
          local src="$SRC_DIR/$car"
          local out="$STAGE/$car"
          if [ ! -f "$src" ]; then
            echo "    warning: $src not found, skipping"
            continue
          fi
          ${carEditBin} "$src" -o "$out" >/dev/null
          # Compare patched-from-pristine against what is LIVE on the system, so
          # we converge: once the live file equals our output, this is a no-op.
          if [ "$(md5 -q "$SYS_DIR/$car")" = "$(md5 -q "$out")" ]; then
            echo "    $car: already patched"
          else
            echo "    $car: needs patching"
            NEED_INSTALL=1
          fi
        done

        if [ "$NEED_INSTALL" -eq 0 ]; then
          umount "$PRISTINE" 2>/dev/null || true
          return 0
        fi

        # Detect mount by content rather than `mount` output: if the system
        # tree is already visible through $MOUNT, we're good. Avoids
        # EINPROGRESS when a previous activation left the volume mounted.
        if [ ! -d "$MOUNT/$RES_REL" ]; then
          echo "    mounting $BASE_DISK at $MOUNT (RW)"
          mount -o nobrowse -t apfs "$BASE_DISK" "$MOUNT"
        fi

        for car in "''${targets[@]}"; do
          local out="$STAGE/$car"
          local target="$MOUNT/$RES_REL/$car"
          if [ -f "$out" ]; then
            cp "$out" "$target"
            echo "    installed: $car"
          fi
        done

        echo "    blessing modified snapshot"
        bless --mount "$MOUNT" --bootefi --create-snapshot
        umount "$PRISTINE" 2>/dev/null || true
        echo "    square-corners: REBOOT to apply"
      }
      _squareCornersPatchCars
    '';
  };
}
