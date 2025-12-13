#!/usr/bin/env nu --stdin

use "../hover.nu" *

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Wi-Fi\""
    "icon.padding_left=0"
    "icon.padding_right=0"
    "label.padding_left=0"
    "label.padding_right=0"
    "padding_left=0"
    "padding_right=0"
  ]

  match $env.SENDER {
    "mouse.entered" => {
      hover_item "wifi"
    }
    "mouse.exited" => {
      unhover_item "wifi"
    }
    "wifi_hover" => {
      if ($env.HOVERED == "true") {
        sketchybar --set "wifi_background" "label.background.color=0x33ffffff" "icon.background.color=0x00000000"
      } else {
        sketchybar --set "wifi_background" "label.background.color=0x00000000" "icon.background.color=0x00000000"
      }
    }
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props --subscribe $"($env.NAME)" mouse.entered mouse.exited wifi_hover
    }
  }
}
