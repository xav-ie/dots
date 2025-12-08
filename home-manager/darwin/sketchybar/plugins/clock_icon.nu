#!/usr/bin/env nu --stdin

def main [] {
  let hour = (date now | format date "%-I" | into int)

  let icon = match $hour {
    12 => "󱑖 "
    1  => "󱑋 "
    2  => "󱑌 "
    3  => "󱑍 "
    4  => "󱑎 "
    5  => "󱑏 "
    6  => "󱑐 "
    7  => "󱑑 "
    8  => "󱑒 "
    9  => "󱑓 "
    10 => "󱑔 "
    11 => "󱑕 "
    _ => "" # Default case for any unexpected value
  }

  # real-width = 15
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Clock\""
    "icon.font.size=18.0"
    "icon.padding_left=5"
    "icon.padding_right=5"
    "label.padding_left=0"
    "label.padding_right=0"
    "label.width=0"
    "label="
    "padding_left=0"
    "padding_right=0"
    "update_freq=30"
    $"icon=($icon)"
  ]

  match $env.SENDER {
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props --subscribe $"($env.NAME)" mouse.entered mouse.exited
    }
    "mouse.entered" => {
      # ensure this state "wins"
      sleep 4ms
      sketchybar --trigger "clock_hover" HOVERED=true
    }
    "mouse.exited" => {
      sketchybar --trigger "clock_hover" HOVERED=false
    }
    "routine" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
    _ => {
      print $"clock: ignoring event ($env.SENDER)"
    }
  }
}
