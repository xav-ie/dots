#!/usr/bin/env nu --stdin

use "../hover.nu" *

def main [] {
   let item_props = [
    "label.padding_left=4"
    "label.padding_right=4"
    "icon.background.drawing=on"
    "display=active"
    "icon.background.image.scale=0.80"
    "click_script=open -a 'Mission Control'"
  ]

  match $env.SENDER {
    "front_app_switched" => {
      sketchybar --set $"($env.NAME)" $"label=($env.INFO)" $"icon.background.image=app.($env.INFO)"
    }
    "mouse.entered" => {
      hover_item "front_app"
    }
    "mouse.exited" => {
      unhover_item "front_app"
    }
    "front_app_hover" => {
      if ($env.HOVERED == "true") {
        sketchybar --set $"($env.NAME)" "label.background.color=0x33ffffff"
      } else {
        sketchybar --set $"($env.NAME)" "label.background.color=0x00000000"
      }
    }
    "mouse.exited.global" => {
      sleep 2ms
      unhover_all
    }
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props --subscribe $"($env.NAME)" mouse.entered mouse.exited front_app_hover
    }
  }
}
