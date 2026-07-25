#!/usr/bin/env nu --stdin

# hidewin — sketchybar item that OWNS the capture-hiding toggle's icon.
#
# Mirrors control_center.nu (an icon-only image button): renders the round
# iris/pupil glyph (`record.circle` — a ring + centre dot, no eye outline) via
# `sketchybar-icons`, white in Normal mode and orange when Screenshare Mode is
# active (every app hidden from capture, for a meeting). Sized to MATCH the
# neighbouring control_center icon (POINT_SIZE 14 in a MIN_WIDTH canvas, drawn
# at background.image.scale 0.5), with the same zeroed paddings so it doesn't
# overlap the volume icon. Hover highlight is painted by sketchybar-hoverd onto
# icon.background.color (its `hidewin -> icon_only` map entry).
#
# The hidewin-bar agent only PUBLISHES state: it writes ~/.cache/hidewin/mode
# and posts com.x.hidewin.mode-changed, which sketchybarrc binds to the
# `hidewin_mode` event this item subscribes to. Clicking runs `hidewin panel
# <x>` so the agent opens the manager panel just below this item.

const CACHE = "~/.cache/hidewin" | path expand
const POINT_SIZE = 14
const MIN_WIDTH = 26

def render [mode: string] {
  let color = if $mode == "on" { "0xffffa000" } else { "0xffffffff" }
  let out = $"($CACHE)/bar-($mode)-($POINT_SIZE).png"
  if not ($out | path exists) {
    mkdir $CACHE
    (sketchybar-icons symbol
      --symbol record.circle
      --point-size $POINT_SIZE --scale 2 --min-width $MIN_WIDTH
      --palette $color --out $out)
  }
  $out
}

def main [] {
  match $env.SENDER {
    "mouse.clicked" => {

      # Open the manager panel under this item; pass our left-edge x.
      let x = (try {
        sketchybar --query $env.NAME | from json | get bounding_rects | values | first | get origin.0
      } catch { null })
      if $x == null { hidewin panel } else { hidewin panel $"($x)" }
    }
    _ => {
      # forced (startup) / hidewin_mode (state change): (re)render the icon.
      # Static geometry (padding/width/background) lives in the item's --add in
      # sketchybarrc so it's correct from creation and can't regress if this
      # render errors; here we only set the mode-dependent image.
      let mode = (
        try {
          open $"($CACHE)/mode" | str trim
        } catch { "off" }
      )
      let out = (render $mode)
      sketchybar --set $env.NAME $"icon.background.image=($out)"
    }
  }
}
