#!/usr/bin/env nu --stdin

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Control Center\""
    "icon.font.size=16.0"
    "icon.padding_left=5"
    "icon.padding_right=8"
    "icon=􀜊 "
    "label.padding_left=0"
    "label.padding_right=0"
    "padding_left=0"
    "padding_right=0"
  ]

  match $env.SENDER {
    "mouse.entered" => {
      sketchybar --trigger "control_center_hover" HOVERED=true
    }
    "mouse.exited" => {
      sketchybar --trigger "control_center_hover" HOVERED=false
    }
    "control_center_hover" => {
      if ($env.HOVERED == "true") {
        sketchybar --set $"($env.NAME)" "label.background.color=0x00000000" "icon.background.color=0x33ffffff"
      } else {
        sketchybar --set $"($env.NAME)" "label.background.color=0x00000000" "icon.background.color=0x00000000"
      }
    }
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props --subscribe $"($env.NAME)" mouse.entered mouse.exited control_center_hover
    }
  }
}
