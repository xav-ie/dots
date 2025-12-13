#!/usr/bin/env nu --stdin

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Battery\""
    "icon.padding_left=0"
    "icon.padding_right=0"
    "label.padding_left=35"
    "label.padding_right=5"
    "label.width=75"
    "padding_left=-35"
    "padding_right=0"
  ]

  match $env.SENDER {
    "forced" => {
      let percentage = (pmset -g batt | lines | last
                       | parse -r '(?<percent>\d?\d?\d)%'
                       | first | get percent
                       | fill --alignment right --character ' ' --width 3)

      sketchybar --set $"($env.NAME)" ...$item_props $"label=($percentage)%" --subscribe battery battery_change mouse.entered mouse.exited battery_hover
    }
    "battery_change" => {
      sketchybar --set $"($env.NAME)" $"label=($env.BATTERY | fill --alignment right --character ' ' --width 3)%"
    }
    "mouse.entered" => {
      sleep 1ms
      sketchybar --trigger "battery_hover" HOVERED=true
    }
    "mouse.exited" => {
      sketchybar --trigger "battery_hover" HOVERED=false
    }
    "battery_hover" => {
      if ($env.HOVERED == "true") {
        sketchybar --set $"($env.NAME)" "label.background.color=0x33ffffff"
      } else {
        sketchybar --set $"($env.NAME)" "label.background.color=0x00000000"
      }
    }
  }
}
