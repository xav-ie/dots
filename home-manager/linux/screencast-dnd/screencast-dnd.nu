#!/usr/bin/env nu

# Detect any active xdg-desktop-portal-hyprland screencast PipeWire node.
# xdph creates streams with media.class "Video/Source" and names them
# "xdph-streaming-<rand>" — see xdph src/portals/Screencopy.cpp. On NixOS the
# node.name gets hijacked by the wrapped binary's process name, but the
# intended name lands in media.name, so we filter on that.
def is-casting []: nothing -> bool {
  pw-dump
  | from json
  | where {|n| ($n.type? | default "") == "PipeWire:Interface:Node" }
  | any {|n|
    let class = ($n.info?.props?."media.class"? | default "")
    let media_name = ($n.info?.props?."media.name"? | default "")
    $class == "Video/Source" and ($media_name | str starts-with "xdph-streaming-")
  }
}

def safe-casting [] {
  try { is-casting } catch { false }
}

def dnd-get []: nothing -> bool {
  let result = try { ^swaync-client --get-dnd --skip-wait | str trim } catch { "" }
  $result == "true"
}

def dnd-set [on: bool] {
  let arg = if $on { "--dnd-on" } else { "--dnd-off" }
  try { ^swaync-client $arg --skip-wait | ignore }
}

def main [] {
  mut casting = (safe-casting)
  # Remember the user's DND preference so we can restore it after casting.
  # On startup-during-cast we can't know the pre-cast value, so we just
  # use whatever DND is currently set to as our best guess.
  mut pre_cast_dnd = (dnd-get)
  if $casting { dnd-set true }

  # pw-mon streams PipeWire events; --print-separator emits a blank line
  # after each, so we re-query only on actual changes — zero polling.
  for line in (pw-mon --no-colors --hide-props --hide-params --print-separator | lines) {
    if $line != "" { continue }
    let current = (safe-casting)
    if $current == $casting { continue }

    if $current {
      $pre_cast_dnd = (dnd-get)
      dnd-set true
    } else {
      dnd-set $pre_cast_dnd
    }
    $casting = $current
  }
}
