#!/usr/bin/env nu --stdin

# The volume_change event supplies a $INFO variable in which the current volume
# percentage is passed to the script.
def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/open_volume_control.scpt"
    "icon.padding_left=0"
    "icon.padding_right=0"
    "label.padding_left=29"
    "label.padding_right=0"
    "label.width=67"
    "padding_left=-29"
    "padding_right=0"
  ];

  match $env.SENDER {
    "volume_change" => {
      let volume = ($env.INFO | fill --alignment right --character ' ' --width 3)
      sketchybar --set $"($env.NAME)" $"label=($volume)%"
    }
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
  }
}
