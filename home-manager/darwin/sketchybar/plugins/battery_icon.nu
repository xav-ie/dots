#!/usr/bin/env nu --stdin

use "../hover.nu" *

def main [] {
  let item_props = [
    "alias.update_freq=0"
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Battery\""
    "icon.padding_left=0"
    "icon.padding_right=0"
    "label.padding_left=0"
    "label.padding_right=0"
    "padding_left=0"
    "padding_right=0"
  ]

  match $env.SENDER {
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props --subscribe $"($env.NAME)" battery_change mouse.entered mouse.exited
    }
    "battery_change" => {
      sketchybar --set $"($env.NAME)" $"alias.update_freq=1"
      # give time for it to update the icon
      sleep 1sec
      # go back to not updating
      sketchybar --set $"($env.NAME)" $"alias.update_freq=0"
    }
    "mouse.entered" => {
      hover_item "battery"
    }
    "mouse.exited" => {
      unhover_item "battery"
    }
    _ => {
      print $"Unknown event: ($env.SENDER)"
    }
  }
}
