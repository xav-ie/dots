#!/usr/bin/env nu --stdin

# Native analog clock icon. Hands sketchybar a PNG rendered by `sketchybar-icons
# clock`, replacing the old Nerd-Font `nf-md-clock_time_*` glyphs (Material Design
# Icons that clashed with the natively-rendered battery/wifi icons and only snap
# to the 12 hour poses). The drawn face is accurate to the minute — white ring +
# white hour hand, and a filled red minute hand (kite-shaped, like the hour hand)
# so it stays legible at this size (a bare red line all but vanished on the bar).
#
# Refreshed on the item's `update_freq` (routine); the cache key is the current
# HH-MM so a given minute renders once and sketchybar reloads on the path change.

const CACHE_DIR = ("~/.cache/sketchybar" | path expand)
# On-screen icon height in px (= the clock's diameter; rendered at 2x, drawn at
# background.image.scale 0.5). Sized to sit alongside the wifi/battery glyphs.
# In the cache filename so bumping it busts stale PNGs.
const POINT_SIZE = 18
const FACE_COLOR = "0xffffffff" # ring + hour hand (white)
const MINUTE_COLOR = "0xffff453a" # minute hand (red — matches the low-battery red)
# Bump when the renderer's clock design changes: it's in the cache filename, so a
# new value forces already-rendered minutes to re-render instead of showing stale
# PNGs from the previous look.
const STYLE = "v2"

# Render (or reuse) the PNG for the current time and return its path. The
# filename encodes HH-MM so (a) each minute renders once, and (b) sketchybar
# reloads whenever the path changes.
def render [] {
  let now = (date now)
  let hour = ($now | format date "%-H" | into int)
  let minute = ($now | format date "%-M" | into int)
  let out = $"($CACHE_DIR)/clock-($hour)-($minute)-($POINT_SIZE)-($STYLE).png"
  if not ($out | path exists) {
    sketchybar-icons clock --hour $hour --minute $minute --point-size $POINT_SIZE --scale 2 --color $FACE_COLOR --minute-color $MINUTE_COLOR --out $out
  }
  $out
}

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Clock\""
    "icon.background.drawing=on"
    "icon.background.image.scale=0.5"
    # sketchybar LEFT-aligns a background image within icon.width; leave it 0 and
    # the 16px PNG overflows right, under clock.nu's negative label.padding, so it
    # overlaps "Thu". Reserve the on-screen image width (POINT_SIZE px at
    # image.scale 0.5) plus a couple px, then the right pad separates it cleanly
    # from the time label sitting to this item's right.
    $"icon.width=($POINT_SIZE + 2)"
    "icon.padding_left=5"
    "icon.padding_right=15"
    "label.padding_left=0"
    "label.padding_right=0"
    "label.width=0"
    "label="
    # Item-level left pad opens a gap to the wifi item on the left WITHOUT moving
    # the clock image or the time (both anchored on the right), so the clock's
    # hover highlight (painted on the `clock` item's label.background, extended
    # left to wrap this icon) ends exactly where the wifi hover background does
    # — the two highlights touch instead of overlapping.
    "padding_left=5"
    "padding_right=0"
    "update_freq=30"
  ]

  match $env.SENDER {
    "forced" => {
      let out = (render)
      sketchybar --set $"($env.NAME)" ...$item_props $"icon.background.image=($out)"
    }
    "routine" => {
      let out = (render)
      sketchybar --set $"($env.NAME)" $"icon.background.image=($out)"
    }
    _ => {
      print $"clock_icon: ignoring event ($env.SENDER)"
    }
  }
}
