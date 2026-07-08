#!/usr/bin/env nu --stdin

# Item shell for the speaker icon. The icon image — and its per-level changes —
# is rendered and driven by volume.nu's tween (see `vol-icon-image` there) so it
# fills through its states in step with the counting number. This plugin only
# owns the static item props + the hover box, so it no longer subscribes to
# volume_change (volume.nu is the single owner of the image, which avoids the two
# items fighting over it mid-tween).
const ICON_WIDTH = 24

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
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
    _ => { }
  }
}
