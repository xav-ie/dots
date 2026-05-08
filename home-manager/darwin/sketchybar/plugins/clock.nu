#!/usr/bin/env nu --stdin

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
      sketchybar --set $"($env.NAME)" ...$item_props
    }
    "routine" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
    _ => {
      print $"clock: ignoring event ($env.SENDER)"
    }
  }
}
