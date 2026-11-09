#!/usr/bin/env nu --stdin

# Native Wi-Fi icon. Reads live signal via CoreWLAN (`sketchybar-icons wifi`,
# which needs no Location permission because it never touches the SSID) and
# renders Apple's own `wifi` SF Symbol at a variable value so the arcs fill by
# signal strength — exactly like Control Center. Replaces the old
# `Control Center,WiFi` alias, which mirrored the real menu-bar item by
# continuously screen-recording it.
#
# Driven by `wifi_change`, emitted by the sketchybar-wifi daemon straight off
# CoreWLAN events (the same ones Control Center listens to) — that's what makes
# this instant — and again once configd settles routes/flags after any network
# change, which is what catches hotspot tether on/off. All push — nothing
# polls, so there is deliberately no `update_freq` on the item.

const CACHE_DIR = "~/.cache/sketchybar" | path expand
# On-screen icon height in px (rendered at 2x, drawn at background.image.scale
# 0.5). Sized to match the neighbouring control_center / clock glyphs. Included
# in the cache filename so bumping it busts stale PNGs.
const POINT_SIZE = 14
# Pad the rendered PNG to this on-screen width (points) with the glyph centred,
# so the hover-highlight button is a touch narrower than control_center. Paired
# with icon.width below (which sketchybar left-aligns the image within).
const MIN_WIDTH = 26

# Map the arc count `sketchybar-icons` reports (0..3) to a variableValue the
# `wifi` symbol renders distinctly. Its bands are ~[0,0.33)=1 arc, [0.33,0.66)=2
# arcs, [0.66,1]=3 arcs, so values must land clearly inside a band. 0 = no arcs
# (the dimmed "searching" glyph).
const SIGNAL_VALUES = [0.0 0.2 0.5 1.0]
# The white Apple draws the `wifi` glyph's unfilled arcs in (30%), for dimming
# glyphs that have no variable value.
const DIM = "0x4dffffff"

# Parse `power=on associated=yes ip=yes internet=online level=3 ...` into a
# record. `wifi_change` carries the daemon's line in $WIFI_STATE; otherwise
# read it fresh.
def read-wifi [] {
  $env.WIFI_STATE?
  | default { sketchybar-icons wifi }
  | str trim
  | split row " "
  | reduce --fold {} {|it, acc|
      let kv = $it | split row "="
      $acc | insert $kv.0 $kv.1
    }
}

# True when tethered to a Personal Hotspot, via Location-free signals (SSID
# would need Location permission): macOS marks Wi-Fi "expensive" when the
# network's beacon carries Apple's personal-hotspot element (iPhones, and
# Android hotspots running Tetherbug), and iPhone USB/Bluetooth
# tethering hands out gateway 172.20.10.1. en0's IsExpensive lingers in
# ipconfig after leaving the hotspot, so it only counts while CoreWLAN says
# Wi-Fi is associated. Full paths since the launchd agent's PATH doesn't include
# /sbin or /usr/sbin.
def is-hotspot [wifi: record] {
  let expensive = ($wifi.associated? == "yes") and (
    do -i { /usr/sbin/ipconfig getsummary en0 } | complete | get stdout | default ""
    | str contains "IsExpensive : TRUE")
  $expensive or (do -i { /sbin/route -n get default } | complete | get stdout | default ""
    | str contains "gateway: 172.20.10.1")
}

# Render (or reuse) the PNG for the current state; return its path. Filename is
# derived from the appearance so sketchybar reloads on change and skips
# re-rendering when unchanged.
def render [] {
  let state = (read-wifi)
  let associated = ($state.associated? | default "no") == "yes"
  # A missing `ip` field means a sketchybar-icons that doesn't report it, so it
  # counts as present.
  let has_ip = ($state.ip? | default "yes") == "yes"
  # Problems on a joined network come first, so a dead hotspot doesn't show the
  # working-hotspot glyph.
  let spec = if $associated and not $has_ip and (is-hotspot $state) {
    # Connecting to a hotspot: its glyph at the dimmed arcs' 30% white.
    {sym: "personalhotspot", value: null, key: "hotspot-pending", color: $DIM}
  } else if $associated and not $has_ip {
    # Still connecting: joined, but DHCP hasn't produced an address. Control
    # Center draws the plain wifi glyph with its arcs unfilled — variableValue
    # 0 dims them exactly that way.
    {sym: "wifi", value: 0.0, key: "pending"}
  } else if $associated and $state.internet? == "captive" {
    # A captive portal is waiting for login: full arcs with a lock badge.
    {sym: "wifi", value: 1.0, badge: "lock.fill", key: "captive"}
  } else if $associated and $state.internet? == "offline" {
    # Joined with an address, but connections don't get past the access point.
    {sym: "wifi.exclamationmark", value: null, key: "nointernet"}
  } else if (is-hotspot $state) {
    # Works even if Wi-Fi is off and it's USB/BT tethered.
    {sym: "personalhotspot", value: null, key: "hotspot"}
  } else if ($state.power? | default "on") != "on" {
    {sym: "wifi.slash", value: null, key: "off"}
  } else if not $associated {
    # Radio on but not joined yet: macOS is still trying, so this is the same
    # connecting glyph.
    {sym: "wifi", value: 0.0, key: "pending"}
  } else {
    let v = $SIGNAL_VALUES | get ($state.level | into int)
    {
      sym: "wifi"
      value: $v
      key: $"on-($v)"
    }
  }

  let color = $spec.color? | default "0xffffffff"
  let out = $"($CACHE_DIR)/wifi-($spec.key)-($POINT_SIZE)-w($MIN_WIDTH).png"
  if not ($out | path exists) {
    let badge = if $spec.badge? != null { [--badge $spec.badge] } else { [] }
    if $spec.value == null {
      sketchybar-icons symbol --symbol $spec.sym --point-size $POINT_SIZE --scale 2 --min-width $MIN_WIDTH --color $color --out $out
    } else {
      sketchybar-icons symbol --symbol $spec.sym --value $spec.value ...$badge --point-size $POINT_SIZE --scale 2 --min-width $MIN_WIDTH --color $color --out $out
    }
  }
  $out
}

def main [] {

  # Geometry (icon.width=26, the bg_only highlight background) is owned by the
  # `sb-icon-item wifi` primitive + its --extra in sketchybarrc.nu — here we set
  # only the icon image. MIN_WIDTH centres the glyph WITHIN that footprint; no
  # x-shift nudge is needed once the footprint tiles cleanly.
  match $env.SENDER {
    "forced" => {
      let out = (render)
      sketchybar --set $"($env.NAME)" $"icon.background.image=($out)"
      # The one-shot read can't see the daemon's path-based verdict, so ask the
      # daemon to re-send its line; it arrives as a wifi_change.
      sketchybar-icons wifi --refresh
    }
    "wifi_change" | "routine" => {
      let out = (render)
      sketchybar --set $"($env.NAME)" $"icon.background.image=($out)"
    }
    _ => {
      print $"wifi: ignoring event ($env.SENDER)"
    }
  }
}
