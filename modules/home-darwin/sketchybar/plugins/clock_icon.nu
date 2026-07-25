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

const CACHE_DIR = "~/.cache/sketchybar" | path expand
# On-screen icon height in px (= the clock's diameter; rendered at 2x, drawn at
# background.image.scale 0.5). Sized to sit alongside the wifi/battery glyphs.
# In the cache filename so bumping it busts stale PNGs.
const POINT_SIZE = 18
# Centre the face in the cluster's icon box (= sb-cluster clock icon_w = 24), the
# same --min-width mechanism as the volume speaker / wifi fan. Replaces the old
# bespoke icon.padding_left/right + item padding that hand-placed the face. In the
# cache filename so a change busts stale PNGs.
const MIN_WIDTH = 24
const FACE_COLOR = "0xffffffff" # ring + hour hand (white)
const MINUTE_COLOR = "0xffff453a" # minute hand (red — matches the low-battery red)
# Bump when the renderer's clock design changes: it's in the cache filename, so a
# new value forces already-rendered minutes to re-render instead of showing stale
# PNGs from the previous look.
const STYLE = "v3"

# Render (or reuse) the PNG for the current time and return its path. The
# filename encodes HH-MM so (a) each minute renders once, and (b) sketchybar
# reloads whenever the path changes.
def render [] {
  let now = (date now)
  let hour = $now | format date "%-H" | into int
  let minute = $now | format date "%-M" | into int
  let out = $"($CACHE_DIR)/clock-($hour)-($minute)-($POINT_SIZE)-($STYLE)-w($MIN_WIDTH).png"
  if not ($out | path exists) {
    sketchybar-icons clock --hour $hour --minute $minute --point-size $POINT_SIZE --scale 2 --min-width $MIN_WIDTH --color $FACE_COLOR --minute-color $MINUTE_COLOR --out $out
  }
  $out
}

def main [] {

  # Geometry (icon.width=24 and all paddings) is owned by the `sb-cluster clock`
  # primitive in sketchybarrc.nu — this plugin sets only CONTENT (the face image),
  # centred in its box by the renderer's --min-width above. Both `forced`
  # (startup) and `routine` (the update_freq tick) refresh it.
  match $env.SENDER {
    "forced" | "routine" => {
      let out = (render)
      sketchybar --set $"($env.NAME)" $"icon.background.image=($out)"
    }
    _ => {
      print $"clock_icon: ignoring event ($env.SENDER)"
    }
  }
}
