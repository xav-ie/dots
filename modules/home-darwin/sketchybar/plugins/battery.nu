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
      # pmset can append extra lines (e.g. "Battery Warning: Early") below the
      # InternalBattery line, so don't rely on `lines | last`. Parse straight
      # for the percent token instead.
      let percentage = (pmset -g batt
                       | parse -r '(?<percent>\d?\d?\d)%'
                       | get percent
                       | first
                       | fill --alignment right --character ' ' --width 3)

      sketchybar --set $"($env.NAME)" ...$item_props $"label=($percentage)%"
    }
    "battery_change" => {
      sketchybar --set $"($env.NAME)" $"label=($env.BATTERY | fill --alignment right --character ' ' --width 3)%"
    }
  }
}
