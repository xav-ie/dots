#!/usr/bin/env nu --stdin

def main [] {
  let label = date now | format date "%a %b %-d %-I:%M%p"
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Clock\""
    "icon.width=0"
    "label.padding_left=25"
    # Was -26 (a tight overlap tuned for the old Nerd-Font clock glyph, which
    # carried side-bearing whitespace). The native clock PNG has none, so -26
    # pulled "Thu" flush against it; -23 restores a clean gap to the clock icon.
    "padding_left=-22"
    "padding_right=0"
    "update_freq=30"
    $"label=($label)"
  ]

  match $env.SENDER {
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
    "routine" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
    _ => {
      print $"clock: ignoring event ($env.SENDER)"
    }
  }
}
