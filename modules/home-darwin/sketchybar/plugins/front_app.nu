#!/usr/bin/env nu --stdin

# Render an SF Symbol glyph to a stable path once, then only reference it.
# point-size 16 @ scale 2 -> a 32px PNG; drawn at icon.background.image.scale=0.5
# that is a clean 2:1 downscale to ~16px (crisp, matching the app icons).
def render_glyph [symbol: string, path: string] {
  if not ($path | path exists) {
    sketchybar-icons symbol --symbol $symbol --point-size 16 --scale 2 --color 0xffffffff --out $path | ignore
  }
  $path
}

# SF Symbol to draw for faceless system agents that momentarily become the front
# app to show a prompt (sketchybar can't resolve a real icon for them). Unmapped
# names fall through to `questionmark`, whose bar label names it, so mapping a new
# one is a one-line edit here.
const fallback_symbols = {
  SecurityAgent: touchid # Touch ID / sudo prompt
  CoreServicesUIAgent: hand.raised.fill # Gatekeeper / quarantine dialogs
  NetAuthAgent: person.badge.key.fill # network share login
  CoreLocationAgent: location.fill # location permission prompt
  UnmountAssistantAgent: eject.fill # disk not ejected properly
  WiFiAgent: wifi # captive portal / join network
  AirPlayUIAgent: airplayvideo # AirPlay PIN entry
}

def draw_app [name: string, cache: string] {

  # Some apps share a localizedName with a background extension that has no
  # launchable URL (e.g. Messages vs com.apple.messages.AssistantExtension).
  # Sketchybar's app.<name> lookup picks the first match and breaks, so we bypass
  # it by passing the bundle id directly for known collisions.
  let icon_key = match $name {
    Messages => "com.apple.MobileSMS"
    _ => $name
  }
  # A mapped fallback ALWAYS wins. A running app — which the front app always is —
  # reports a native icon even when it's a faceless agent with only a blank/generic
  # one (SecurityAgent, etc.), so `app-icon` can't be trusted to route those; we
  # must override by name. Only for unmapped apps do we ask app-icon whether
  # sketchybar has a real icon (0.80) or we should draw a questionmark (0.5).
  let mapped = ($fallback_symbols | get --optional $name)
  let image_args = if $mapped != null {
    let p = (render_glyph $mapped $"($cache)/($mapped).png")
    [$"icon.background.image=($p)" "icon.background.image.scale=0.5"]
  } else if (sketchybar-icons app-icon --name $name | str trim) == "native" {
    [$"icon.background.image=app.($icon_key)" "icon.background.image.scale=0.80"]
  } else {
    let p = (render_glyph questionmark $"($cache)/questionmark.png")
    [$"icon.background.image=($p)" "icon.background.image.scale=0.5"]
  }
  sketchybar --set front_app $"label=($name)" ...$image_args
}

def main [] {
  let cache = $"($env.HOME)/.cache/sketchybar"

  match $env.SENDER {
    "front_app_switched" => {
      draw_app $env.INFO $cache
    }
    "forced" => {
      sketchybar --set front_app "label.padding_left=4" "label.padding_right=4" "icon.background.drawing=on" "display=active" "icon.background.image.scale=0.80" "click_script=open -a 'Mission Control'"
    }
  }
}
