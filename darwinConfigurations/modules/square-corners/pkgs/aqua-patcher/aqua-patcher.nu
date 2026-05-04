# Aqua.car / DarkAqua.car patch helper for squaring the macOS Tahoe window
# corner shape mask. The actual rendition replacement is done by `car-edit`
# (a Swift CLI linking against private CoreUI). This script handles backup,
# install via system-volume mount + bless, and restore. The 1px window rim
# itself is suppressed by the macos-corner-fix dylib, not by this patch.
#
# After macOS point updates the system snapshot is resealed; the
# `services.aqua-patch` darwin module re-runs `aqua-patcher apply` on every
# `darwin-rebuild activate` so the patch is reapplied automatically.

const BACKUP_PRIMARY   = "~/Documents/aqua-car-backup"
const BACKUP_SECONDARY = "~/Desktop"
const SYSTEM_DIR       = "/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources"
const MOUNT_POINT      = "~/live_disk_mnt"
const LIGHT_CAR        = "Aqua.car"
const DARK_CAR         = "DarkAqua.car"
const STAGE_DIR        = "/tmp/aqua-patcher"

def log [msg: string] {
  print $"(ansi cyan)==>(ansi reset) ($msg)"
}

def err [msg: string] {
  print -e $"(ansi red)error:(ansi reset) ($msg)"
  exit 1
}

def md5_of [path: string] {
  ^md5 -q ($path | path expand) | str trim
}

def require_security_disabled [] {
  let sip = ^csrutil status | str downcase
  if not ($sip | str contains "disabled") {
    err "SIP is enabled — boot to Recovery and run: csrutil disable"
  }
  let ar = ^csrutil authenticated-root status | str downcase
  if not ($ar | str contains "disabled") {
    err "Authenticated Root is enabled — boot to Recovery and run: csrutil authenticated-root disable"
  }
}

def base_disk [] {
  let root = ^df / | lines | last | split row -r '\s+' | get 0
  $root | str replace -r 's[0-9]+$' ''
}

def ensure_mount [] {
  let mp = ($MOUNT_POINT | path expand)
  mkdir $mp
  let mounted = (^mount | lines | find $"on ($mp) " | length)
  if $mounted == 0 {
    log $"mounting (base_disk) at ($mp)"
    ^sudo mount -o nobrowse -t apfs (base_disk) $mp
  }
  $mp
}

# ------------------------------------------------------------------------------

def "main backup" [] {
  mkdir ($BACKUP_PRIMARY | path expand)
  for car in [$LIGHT_CAR $DARK_CAR] {
    let src = $"($SYSTEM_DIR)/($car)"
    if not ($src | path exists) { err $"missing system file: ($src)" }
    let dst1 = $"($BACKUP_PRIMARY | path expand)/($car).original"
    let dst2 = $"($BACKUP_SECONDARY | path expand)/($car).original.backup2"
    if (not ($dst1 | path exists)) or ((md5_of $dst1) != (md5_of $src)) {
      cp $src $dst1
      cp $src $dst2
      log $"backed up ($car) md5=(md5_of $src)"
    } else {
      log $"backup of ($car) already current"
    }
  }
}

# Generate a patched .car for one target and return its path. Idempotent — if
# the system file is already patched (md5 matches a fresh car-edit run), the
# returned path will have an md5 equal to the system file.
def stage_one [car: string] {
  mkdir $STAGE_DIR
  let src = $"($SYSTEM_DIR)/($car)"
  let out = $"($STAGE_DIR)/($car)"
  if not ($src | path exists) { err $"missing system file: ($src)" }
  ^car-edit $src -o $out | ignore
  $out
}

def "main apply" [
  --targets: list<string> = ["DarkAqua.car"]   # subset of [Aqua.car, DarkAqua.car]
] {
  require_security_disabled
  main backup

  mut to_install = []
  for car in $targets {
    let staged = stage_one $car
    let staged_md5 = md5_of $staged
    let system_md5 = md5_of $"($SYSTEM_DIR)/($car)"
    if $staged_md5 == $system_md5 {
      log $"($car) already patched, skipping"
    } else {
      log $"($car) needs patching"
      log $"  system: ($system_md5)"
      log $"  staged: ($staged_md5)"
      $to_install = ($to_install | append $car)
    }
  }

  if ($to_install | is-empty) {
    log "nothing to install"
    return
  }

  let mp = (ensure_mount)
  for car in $to_install {
    let staged = $"($STAGE_DIR)/($car)"
    let target = $"($mp)/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources/($car)"
    log $"installing ($car) -> ($target)"
    ^sudo cp $staged $target
  }

  log "blessing the modified volume + creating bootable snapshot"
  ^sudo bless --mount $mp --bootefi --create-snapshot

  log "done. reboot to apply: sudo shutdown -r now"
  log "if dark breaks: switch to Light in System Settings -> Appearance"
}

def "main restore" [which: string = "both"] {
  require_security_disabled
  let cars = if $which == "light" {
    [$LIGHT_CAR]
  } else if $which == "dark" {
    [$DARK_CAR]
  } else if $which == "both" {
    [$LIGHT_CAR $DARK_CAR]
  } else {
    err "usage: aqua-patcher restore [light|dark|both]"
  }
  let mp = (ensure_mount)
  let target = $"($mp)/System/Library/CoreServices/SystemAppearance.bundle/Contents/Resources"
  for car in $cars {
    let src = $"($BACKUP_PRIMARY | path expand)/($car).original"
    if not ($src | path exists) {
      err $"no backup at ($src) — try ($BACKUP_SECONDARY)/($car).original.backup2"
    }
    log $"restoring ($car) from ($src)"
    ^sudo cp $src $"($target)/($car)"
  }
  log "blessing the restored volume"
  ^sudo bless --mount $mp --bootefi --create-snapshot
  log "done. reboot: sudo shutdown -r now"
}

def "main status" [] {
  print $"SIP:                ((^csrutil status | str trim))"
  print $"Authenticated Root: ((^csrutil authenticated-root status | str trim))"
  print $"AMFI boot-args:     ((^nvram boot-args | str trim))"
  print ""
  print "System .car md5s (current):"
  for car in [$LIGHT_CAR $DARK_CAR] {
    print $"  ($car)  ((md5_of $"($SYSTEM_DIR)/($car)"))"
  }
  print ""
  print "Backup md5s:"
  for car in [$LIGHT_CAR $DARK_CAR] {
    let f = $"($BACKUP_PRIMARY | path expand)/($car).original"
    if ($f | path exists) {
      print $"  ($car)  ((md5_of $f))   ($f)"
    } else {
      print $"  ($car)  MISSING"
    }
  }
  print ""
  print "Patched-from-current .car md5s (what `apply` would install):"
  for car in [$LIGHT_CAR $DARK_CAR] {
    let staged = (stage_one $car)
    print $"  ($car)  ((md5_of $staged))"
  }
}

def main [] {
  print "Usage: aqua-patcher <subcommand>"
  print ""
  print "  backup                        copy current Aqua.car & DarkAqua.car to backup locations"
  print "  apply [--targets <list>]      run car-edit on the system .car(s), install patched,"
  print "                                bless a new boot snapshot. Idempotent."
  print "                                Default targets: [DarkAqua.car]"
  print "  restore [light|dark|both]     restore .car(s) from backup, bless, reboot"
  print "  status                        SIP/auth-root state, current/backup/staged md5s"
}
