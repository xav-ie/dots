#!/usr/bin/env nu --stdin

use "../hover.nu" *

def main [] {
  let label = (date now | format date "%a %b %-d %-I:%M%p")
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Clock\""
    "icon.width=0"
    "label.padding_left=25"
    "padding_left=-26"
    "padding_right=0"
    "update_freq=30"
    $"label=($label)"
  ]

  match $env.SENDER {
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props --subscribe $"($env.NAME)" mouse.entered mouse.exited clock_hover
    }
    "mouse.entered" => {
      hover_item "clock"
    }
    "mouse.exited" => {
      unhover_item "clock"
    }
    "clock_hover" => {
      if ($env.HOVERED == "true") {
        sketchybar --set $"($env.NAME)" "label.background.color=0x33ffffff" "icon.background.color=0x33ffffff"
      } else {
        sketchybar --set $"($env.NAME)" "label.background.color=0x00000000" "icon.background.color=0x00000000"
      }
    }
    "routine" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
    _ => {
      print $"clock: ignoring event ($env.SENDER)"
    }
  }
}
