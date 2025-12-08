#!/usr/bin/env nu --stdin

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Wi-Fi\""
    "icon.padding_left=0"
    "icon.padding_right=0"
    "label.padding_left=0"
    "label.padding_right=0"
    "label.width=24"
    "label="
    "padding_left=-28.75"
    "padding_right=0"
  ]

  match $env.SENDER {
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
  }
}
