#!/usr/bin/env nu --stdin

def main [] {

  # Geometry (the 24px icon zone/pull, paddings, update_freq) is owned by the
  # `sb-cluster clock` primitive in sketchybarrc.nu — this plugin sets only
  # CONTENT: the time string. Both `forced` (startup) and `routine` (the
  # update_freq tick) refresh it.
  let label = date now | format date "%a %b %-d %-I:%M%p"
  match $env.SENDER {
    "forced" | "routine" => {
      sketchybar --set $"($env.NAME)" $"label=($label)"
    }
    _ => {
      print $"clock: ignoring event ($env.SENDER)"
    }
  }
}
