#!/usr/bin/env nu --stdin

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

      # Some apps share a localizedName with a background extension that has no
      # launchable URL (e.g. Messages vs com.apple.messages.AssistantExtension).
      # Sketchybar's app.<name> lookup picks the first match and breaks, so we
      # bypass it by passing the bundle id directly for known collisions.
      let icon_key = match $env.INFO {
        Messages => "com.apple.MobileSMS"
        _ => $env.INFO
      }
      sketchybar --set $"($env.NAME)" $"label=($env.INFO)" $"icon.background.image=app.($icon_key)"
    }
    "forced" => {
      sketchybar --set $"($env.NAME)" ...$item_props
    }
  }
}
