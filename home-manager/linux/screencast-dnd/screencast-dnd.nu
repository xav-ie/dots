#!/usr/bin/env nu

# Detect xdg-desktop-portal-hyprland screencasts by parsing pw-mon's event
# stream directly. xdph creates streams with media.class "Video/Source" and
# media.name "xdph-streaming-<rand>" — see xdph src/portals/Screencopy.cpp.

def dnd-get []: nothing -> bool {
  let result = try { ^swaync-client --get-dnd --skip-wait | str trim } catch { "" }
  $result == "true"
}

def dnd-set [on: bool] {
  let arg = if $on { "--dnd-on" } else { "--dnd-off" }
  try { ^swaync-client $arg --skip-wait | ignore }
}

def main [] {
  mut active: list<int> = []
  mut pre_cast_dnd = (dnd-get)

  # Per-block parse state — reset on each blank-line separator.
  mut action = ""
  mut id = -1
  mut is_node = false
  mut is_video_source = false
  mut is_xdph_stream = false

  for line in (pw-mon --no-colors --hide-params --print-separator | lines) {
    if $line == "" {
      let was_casting = (not ($active | is-empty))

      if ($action == "added" or $action == "changed") and $is_node and $is_video_source and $is_xdph_stream and $id >= 0 {
        if not ($id in $active) {
          $active = ($active | append $id)
        }
      } else if $action == "removed" and $id >= 0 and ($id in $active) {
        $active = ($active | where {|x| $x != $id })
      }

      let now_casting = (not ($active | is-empty))
      if $now_casting and not $was_casting {
        $pre_cast_dnd = (dnd-get)
        dnd-set true
      } else if not $now_casting and $was_casting {
        dnd-set $pre_cast_dnd
      }

      $action = ""
      $id = -1
      $is_node = false
      $is_video_source = false
      $is_xdph_stream = false
      continue
    }

    let t = ($line | str trim)
    if $t == "added:" {
      $action = "added"
    } else if $t == "removed:" {
      $action = "removed"
    } else if $t == "changed:" {
      $action = "changed"
    } else if ($t | str starts-with "id:") {
      let parts = ($t | split row " " | where {|p| $p != "" })
      if ($parts | length) >= 2 {
        $id = (try { $parts | get 1 | into int } catch { -1 })
      }
    } else if ($t | str starts-with "type:") {
      $is_node = ($t | str contains "PipeWire:Interface:Node")
    } else if ($t | str starts-with "media.class") {
      $is_video_source = ($t | str contains '"Video/Source"')
    } else if ($t | str starts-with "media.name") {
      $is_xdph_stream = ($t | str contains '"xdph-streaming-')
    }
  }
}
