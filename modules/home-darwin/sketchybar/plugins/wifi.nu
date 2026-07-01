#!/usr/bin/env nu --stdin

# Native Wi-Fi icon. Reads live signal via CoreWLAN (`sketchybar-icons wifi`,
# which needs no Location permission because it never touches the SSID) and
# renders Apple's own `wifi` SF Symbol at a variable value so the arcs fill by
# signal strength — exactly like Control Center. Replaces the old
# `Control Center,WiFi` alias, which mirrored the real menu-bar item by
# continuously screen-recording it.
#
# Driven by the `network_change` event (bound to the
# com.apple.system.config.network_change distributed notification) for instant
# connect/disconnect reaction, plus the item's `update_freq` for slow signal
# refresh.

const CACHE_DIR = ("~/.cache/sketchybar" | path expand)
# On-screen icon height in px (rendered at 2x, drawn at background.image.scale
# 0.5). Sized to match the neighbouring control_center / clock glyphs. Included
# in the cache filename so bumping it busts stale PNGs.
const POINT_SIZE = 14
# Pad the rendered PNG to this on-screen width (points) with the glyph centred,
# so the hover-highlight button is a touch narrower than control_center. Paired
# with icon.width below (which sketchybar left-aligns the image within).
const MIN_WIDTH = 26
# Rightward nudge (points) baked into the PNG, since sketchybar can't move a
# background image. Compensates for the button being shifted by background
# padding, so the fan sits centred in its button (measured 12/11 retina px).
const X_SHIFT = 0.75

# Quantize the 0..1 signal fraction to the wifi glyph's THREE distinct arc
# levels. The `wifi` symbol only has 3 arcs, and its variableValue bands are
# ~[0,0.33)=1 arc, [0.33,0.66)=2 arcs, [0.66,1]=3 arcs — so values must land
# clearly inside a band (0.2 / 0.5 / 1.0), else adjacent levels render alike.
def signal-value [fraction: float] {
  if $fraction >= 0.66 {
    1.0
  } else if $fraction >= 0.33 {
    0.5
  } else {
    0.2
  }
}

# Parse `power=on associated=yes rssi=-56 fraction=0.83` into a record.
def read-wifi [] {
  sketchybar-icons wifi
  | str trim
  | split row " "
  | reduce --fold {} {|it, acc|
      let kv = ($it | split row "=")
      $acc | insert $kv.0 $kv.1
    }
}

# True when tethered to an iPhone Personal Hotspot. iPhone hotspots (over
# Wi-Fi/USB/Bluetooth) hand out the 172.20.10.0/28 subnet with gateway
# 172.20.10.1 — a Location-free signal (SSID would need Location permission).
# Full path since the launchd agent's PATH doesn't include /sbin.
def is-hotspot [] {
  (do -i { /sbin/route -n get default } | complete | get stdout | default ""
    | str contains "gateway: 172.20.10.1")
}

# Render (or reuse) the PNG for the current state; return its path. Filename is
# derived from the appearance so sketchybar reloads on change and skips
# re-rendering when unchanged.
def render [] {
  let color = "0xffffffff"

  # Hotspot takes priority (works even if Wi-Fi is off and it's USB/BT tethered).
  let spec = if (is-hotspot) {
    { sym: "personalhotspot", value: null, key: "hotspot" }
  } else {
    let state = (read-wifi)
    if ($state.power? | default "on") != "on" {
      { sym: "wifi.slash", value: null, key: "off" }
    } else if ($state.associated? | default "no") != "yes" {
      { sym: "wifi.exclamationmark", value: null, key: "noassoc" }
    } else {
      let v = (signal-value ($state.fraction | into float))
      { sym: "wifi", value: $v, key: $"on-($v)" }
    }
  }

  let out = $"($CACHE_DIR)/wifi-($spec.key)-($POINT_SIZE)-w($MIN_WIDTH)-x($X_SHIFT).png"
  if not ($out | path exists) {
    if $spec.value == null {
      sketchybar-icons symbol --symbol $spec.sym --point-size $POINT_SIZE --scale 2 --min-width $MIN_WIDTH --x-shift $X_SHIFT --color $color --out $out
    } else {
      sketchybar-icons symbol --symbol $spec.sym --value $spec.value --point-size $POINT_SIZE --scale 2 --min-width $MIN_WIDTH --x-shift $X_SHIFT --color $color --out $out
    }
  }
  $out
}

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Wi-Fi\""
    "icon.background.drawing=on"
    "icon.background.image.scale=0.5"
    # sketchybar LEFT-aligns a background image within icon.width, so set the
    # width to the padded image's on-screen width (= MIN_WIDTH). The renderer
    # centres the glyph in that padded canvas, so the icon ends up centred in the
    # hover highlight (this item's own background) with no dead space on the
    # right. Width tuned a touch under control_center.
    "icon.width=26"
    "icon.padding_left=0"
    "icon.padding_right=0"
    "label.padding_left=0"
    "label.padding_right=0"
    # The hover highlight is this item's OWN background (painted by
    # sketchybar-hoverd, target `wifi` -> `background.color`). Pre-set the
    # geometry here; the colour starts transparent and the daemon animates it.
    "background.height=24"
    "background.corner_radius=6"
    "background.drawing=on"
    "background.color=0x00000000"
    # Extends the button leftward a hair to meet the control_center button
    # (closing the seam). The fan is re-centred for this via X_SHIFT above.
    "background.padding_left=-1"
    "padding_left=0"
    "padding_right=0"
  ]

  match $env.SENDER {
    "forced" => {
      let out = (render)
      sketchybar --set $"($env.NAME)" ...$item_props $"icon.background.image=($out)"
    }
    "network_change" | "routine" => {
      let out = (render)
      sketchybar --set $"($env.NAME)" $"icon.background.image=($out)"
    }
    _ => {
      print $"wifi: ignoring event ($env.SENDER)"
    }
  }
}
