#!/usr/bin/env nu --stdin

# mic_denoise — sketchybar item that OWNS the RNNoise virtual-mic icon. Same shape
# as hidewin.nu: the mic-denoise agent only PUBLISHES state to
# ~/.cache/mic-denoise/state (on/off/error) and posts com.x.mic-denoise.changed
# (bound to the `mic_denoise_changed` event). Green = denoising, orange = enabled
# but not running (see the panel's status line), white = off. Clicking runs
# `mic-denoise panel <x>` to open the settings panel under this item.

const CACHE = "~/.cache/mic-denoise" | path expand
const POINT_SIZE = 14
const MIN_WIDTH = 26

def render [state: string] {
  let color = match $state {
    on => "0xff30d158"
    error => "0xffffa000"
    _ => "0xffffffff"
  }
  let out = $"($CACHE)/bar-($state)-($POINT_SIZE).png"
  if not ($out | path exists) {
    mkdir $CACHE
    (sketchybar-icons symbol
      --symbol waveform.badge.mic
      --point-size $POINT_SIZE --scale 2 --min-width $MIN_WIDTH
      --palette $color --out $out)
  }
  $out
}

def main [] {
  match $env.SENDER {
    "mouse.clicked" => {
      let x = (try {
        sketchybar --query $env.NAME | from json | get bounding_rects | values | first | get origin.0
      } catch { null })
      if $x == null { mic-denoise panel } else { mic-denoise panel $"($x)" }
    }
    _ => {
      let state = (
        try {
          open $"($CACHE)/state" | str trim
        } catch {
          "off"
        }
      )
      sketchybar --set $env.NAME $"icon.background.image=(render $state)"
    }
  }
}
