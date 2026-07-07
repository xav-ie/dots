#!/usr/bin/env nu --stdin

# Native Control Center icon. Renders the `switch.2` SF Symbol (the macOS
# Control Center two-toggle glyph) to a PNG via `sketchybar-icons`, replacing the
# Maple-Mono Nerd-Font glyph (`􀜊`) so the bar no longer depends on the icon font
# for this item. Fully static — rendered once and cached.
#
# Sized to MATCH the neighbouring wifi icon: same point size, same padded canvas
# width, so the two buttons and their hover highlights line up. The hover
# highlight is painted by sketchybar-hoverd onto this item's icon.background.color
# (see the daemon's `control_center -> icon_only` mapping), behind the PNG.

const CACHE_DIR = "~/.cache/sketchybar" | path expand
# Match wifi.nu: POINT_SIZE 14 glyph centred in a MIN_WIDTH-wide canvas, drawn at
# background.image.scale 0.5 with icon.width = MIN_WIDTH so the button footprint
# (and hover box) is identical to wifi's.
const POINT_SIZE = 14
const MIN_WIDTH = 26

# `switch.2` is a multi-layer symbol; an all-white palette makes both toggles
# solid white (matching the old glyph) instead of the hierarchical dimmed top.
# --min-width centres the glyph in a MIN_WIDTH canvas (symmetric glyph, so no
# x-shift needed).
def render [] {
  let w = "0xffffffff"
  let out = $"($CACHE_DIR)/control-center-($POINT_SIZE)-w($MIN_WIDTH).png"
  if not ($out | path exists) {
    sketchybar-icons symbol --symbol switch.2 --point-size $POINT_SIZE --scale 2 --min-width $MIN_WIDTH --palette $"($w),($w),($w)" --out $out
  }
  $out
}

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Control Center\""
    "icon.background.drawing=on"
    "icon.background.image.scale=0.5"
    $"icon.width=($MIN_WIDTH)"
    "icon.padding_left=0"
    "icon.padding_right=0"
    "label.padding_left=0"
    "label.padding_right=0"
    "label.width=0"
    "label="
    "padding_left=0"
    "padding_right=0"
  ]

  match $env.SENDER {
    "forced" => {
      let out = (render)
      sketchybar --set $"($env.NAME)" ...$item_props $"icon.background.image=($out)"
    }
    _ => {
      print $"control_center: ignoring event ($env.SENDER)"
    }
  }
}
