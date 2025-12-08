#!/usr/bin/env nu --stdin

# The $NAME variable is passed from sketchybar and holds the name of
# the item invoking this script:
# https://felixkratz.github.io/SketchyBar/config/events#events-and-scripting
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
      # ensure this state "wins"
      sleep 4ms
      sketchybar --trigger "clock_hover" HOVERED=true
    }
    "mouse.exited" => {
      sketchybar --trigger "clock_hover" HOVERED=false
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
