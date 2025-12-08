#!/usr/bin/env nu --stdin

# The volume_change event supplies a $INFO variable in which the current volume
# percentage is passed to the script.
def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/open_volume_control.scpt"
    "icon.font.size=14.0"
    "icon.padding_left=0"
    "icon.padding_right=0"
    "icon.width=24"
    "label.padding_left=0"
    "label.padding_right=0"
    "padding_left=0"
    "padding_right=0"
  ];

  match $env.SENDER {
    "volume_change" => {
      let icon = match ($env.INFO | into int) {
        # muted
        0 => "􀊣 "
        # no bars
        1..24 => "􀊡"
        # one bar
        25..49 => "􀊥 "
        # two bars
        50..74 => "􀊧 "
        # three bars
        75..100 => "􀊩 "
      }
      sketchybar --set $"($env.NAME)" $"icon=($icon)"
    }
    "mouse.entered" => {
      sleep 4ms
      sketchybar --trigger "volume_hover" HOVERED=true
    }
    "mouse.exited" => {
      sketchybar --trigger "volume_hover" HOVERED=false
    }
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props --subscribe $"($env.NAME)" mouse.entered mouse.exited volume_change
    }
  }
}
