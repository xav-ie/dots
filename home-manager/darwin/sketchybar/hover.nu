#!/usr/bin/env nu --stdin

const hover_items = [
  "battery"
  "clock"
  "control_center"
  "front_app"
  "volume"
  "wifi"
]

export def unhover_item [item] {
  sketchybar --trigger $"($item)_hover" HOVERED=false
}

export def hover_item [item] {
  sleep 3ms
  sketchybar --trigger $"($item)_hover" HOVERED=true
  sleep 5ms
  let other_items = ($hover_items | where $it != $item)
  $other_items | par-each {|item|
    sketchybar --trigger $"($item)_hover" HOVERED=false
  }
  return;
}

export def unhover_all [] {
  $hover_items | par-each {|item|
    sketchybar --trigger $"($item)_hover" HOVERED=false
  }
  return;
}
