#!/usr/bin/env nu --stdin

def main [] {
  let item_props = [
    "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Battery\""
    "icon.padding_left=0"
    "icon.padding_right=0"
    # Reserves space for the battery icon, with a small margin so the icon isn't
    # flush against the hover box's left edge. Keep label.padding_left paired with
    # the negative padding_left below (that pairing sets the reserved-zone width).
    "label.padding_left=40"
    "label.padding_right=4"
    # No fixed label.width: the label (and its hover highlight) hugs the text so
    # the % sits close to the button's right edge. The icon only shifts when the
    # digit count changes (e.g. 100 -> 99).
    "padding_left=-40"
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
                       | first)

      sketchybar --set $"($env.NAME)" ...$item_props $"label=($percentage)%"
    }
    "battery_change" => {
      sketchybar --set $"($env.NAME)" $"label=($env.BATTERY)%"
    }
  }
}
