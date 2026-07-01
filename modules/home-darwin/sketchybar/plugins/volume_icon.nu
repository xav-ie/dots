#!/usr/bin/env nu --stdin

# Native volume icon. Renders the macOS speaker SF Symbols to PNGs via
# `sketchybar-icons`, replacing the Maple-Mono Nerd-Font glyphs so the bar no
# longer depends on the icon font. The volume_change event supplies $INFO =
# current volume percent.

const CACHE_DIR = ("~/.cache/sketchybar" | path expand)
const POINT_SIZE = 12
# Fixed icon slot (points) so the icon doesn't shift as waves are added: the
# image is LEFT-aligned within it, keeping the speaker body at a fixed x while
# the waves grow to the right (like macOS). Matches the old icon.width.
const ICON_WIDTH = 24

# Map a 0..100 volume to the matching speaker SF Symbol.
def volume-symbol [pct: int] {
  if $pct == 0 {
    "speaker.slash.fill" # muted
  } else if $pct <= 24 {
    "speaker.fill" # no waves
  } else if $pct <= 49 {
    "speaker.wave.1.fill" # one bar
  } else if $pct <= 74 {
    "speaker.wave.2.fill" # two bars
  } else {
    "speaker.wave.3.fill" # three bars
  }
}

# Render (or reuse) the all-white PNG for a speaker symbol; the palette keeps the
# waves solid white (matching the old glyphs) rather than hierarchical-dimmed.
def render [sym: string] {
  let w = "0xffffffff"
  let out = $"($CACHE_DIR)/volume-($sym)-($POINT_SIZE).png"
  if not ($out | path exists) {
    sketchybar-icons symbol --symbol $sym --point-size $POINT_SIZE --scale 2 --palette $"($w),($w),($w),($w)" --out $out
  }
  $out
}

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/open_volume_control.scpt"
    "icon.background.drawing=on"
    "icon.background.image.scale=0.5"
    $"icon.width=($ICON_WIDTH)"
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
    "volume_change" => {
      let out = (render (volume-symbol ($env.INFO | into int)))
      sketchybar --set $"($env.NAME)" $"icon.background.image=($out)"
    }
    "forced" => {
      # Render the current volume on load so the icon isn't blank before the first
      # volume_change (mute takes priority over the level).
      let muted = ((osascript -e "output muted of (get volume settings)" | str trim) == "true")
      let vol = (osascript -e "output volume of (get volume settings)" | str trim | into int)
      let sym = (if $muted { "speaker.slash.fill" } else { (volume-symbol $vol) })
      let out = (render $sym)
      sketchybar --set $"($env.NAME)" ...$item_props $"icon.background.image=($out)"
    }
    _ => {
      print $"volume_icon: ignoring event ($env.SENDER)"
    }
  }
}
