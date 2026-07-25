#!/usr/bin/env nu --stdin

def main [] {

  # Geometry (the 36px icon zone/pull, paddings) is owned by the `sb-cluster
  # battery` primitive in sketchybarrc.nu — this plugin sets only CONTENT (the %).
  match $env.SENDER {
    "forced" => {

      # pmset can append extra lines (e.g. "Battery Warning: Early") below the
      # InternalBattery line, so don't rely on `lines | last`. Parse straight
      # for the percent token instead.
      let percentage = (pmset -g batt
                       | parse -r '(?<percent>\d?\d?\d)%'
                       | get percent
                       | first)

      sketchybar --set $"($env.NAME)" $"label=($percentage)%"
    }
    "battery_change" => {
      sketchybar --set $"($env.NAME)" $"label=($env.BATTERY)%"
    }
  }
}
