#!/usr/bin/env nu --stdin

# virtual_headset — the one mic item: virtual-headset's agent plus call mute.
# Same shape as hidewin.nu: the virtual-headset agent only PUBLISHES state and posts
# com.github.virtual-headset.changed (bound to the `virtual_headset_changed` event):
#   ~/.cache/virtual-headset/state  on / raw / muted / standby / error
#   ~/.cache/virtual-headset/call   none / muted / unmuted, from the call app's LEDs
#
# In a call the icon is the call's mic: white mic.slash = muted, red mic = LIVE,
# orange mic = live but nothing is reaching Virtual_Headset_Microphone. The call
# is one paired with the Virtual_Headset HID device, or a Zoom desktop meeting
# read from Zoom's own "Meeting" menu over Accessibility (English-only
# "Mute/Unmute audio" labels).
# Outside calls it's a plain outline mic: white, or orange when the agent is
# failing (see the panel's status line).
#
# Left click opens the agent's panel under this item (it has a Mute row in calls);
# right click toggles mute. A mute press outside a call flashes an orange
# mic.slash (the agent leaves a `nudge` marker).

const CACHE = "~/.cache/virtual-headset" | path expand
const POINT_SIZE = 12
const MIN_WIDTH = 26
# Optical nudge (points, +right): mic.slash's diagonal makes a geometrically
# centred glyph read as left-leaning.
const X_SHIFT = 0.5

# Zoom's "Meeting" menu has one audio item whose title flips: "Unmute audio"
# (currently muted) vs "Mute audio" (currently live). Absent/erroring => not in a
# meeting. Scan by name, not index, so Zoom reordering the menu can't break it.
const ZOOM_READ_OSA = '
tell application "System Events" to tell process "zoom.us"
  try
    repeat with mi in menu items of menu 1 of menu bar item "Meeting" of menu bar 1
      set n to name of mi
      if n is not missing value then
        if n contains "Unmute audio" then return "muted"
        if n contains "Mute audio" then return "unmuted"
      end if
    end repeat
  end try
  return "none"
end tell'

# Click that same menu item, returning the state BEFORE the click: Zoom delays
# refreshing the title after a programmatic click, so re-reading would race it.
const ZOOM_TOGGLE_OSA = '
tell application "System Events" to tell process "zoom.us"
  try
    repeat with mi in menu items of menu 1 of menu bar item "Meeting" of menu bar 1
      set n to name of mi
      if n is not missing value then
        if n contains "Unmute audio" then
          click mi
          return "muted"
        else if n contains "Mute audio" then
          click mi
          return "unmuted"
        end if
      end if
    end repeat
  end try
  return "none"
end tell'

def cached [file: string, fallback: string] {
  try { open $"($CACHE)/($file)" | str trim } catch { $fallback }
}

# Skip the osascript round trip when Zoom desktop isn't even running.
def zoom-desktop [osa: string] {
  if (pgrep -x zoom.us | complete).exit_code != 0 { return "none" }
  osascript -e $osa | str trim
}

# "none" / "muted" / "unmuted": a Zoom desktop meeting wins over a headset call.
def call-state [] {
  let zoom = (zoom-desktop $ZOOM_READ_OSA)
  if $zoom != "none" { $zoom } else { cached call none }
}

def glyph [symbol: string, size: int, color: string, key: string, --x-shift: float = 0.0] {
  let out = $"($CACHE)/bar-($key)-($size)-w($MIN_WIDTH).png"
  if not ($out | path exists) {
    mkdir $CACHE
    # Two-entry palette so multi-layer glyphs like mic.slash render flat.
    (sketchybar-icons symbol
      --symbol $symbol
      --point-size $size --scale 2 --min-width $MIN_WIDTH --x-shift $x_shift
      --palette $"($color),($color)" --out $out)
  }
  $out
}

def render [call: string, state: string] {
  match [$call $state] {
    [muted _] => (glyph mic.slash.fill $POINT_SIZE "0xffffffff" call-muted --x-shift $X_SHIFT)
    [unmuted on] | [unmuted raw] => (glyph mic.fill $POINT_SIZE "0xffff453a" call-live --x-shift $X_SHIFT)
    [unmuted _] => (glyph mic.fill $POINT_SIZE "0xffffa000" call-live-broken --x-shift $X_SHIFT)
    [_ error] => (glyph mic $POINT_SIZE "0xffffa000" idle-error --x-shift $X_SHIFT)
    _ => (glyph mic $POINT_SIZE "0xffffffff" idle --x-shift $X_SHIFT)
  }
}

def sync [] {
  # A mute press with no call to mute: flash before settling on the real state.
  let nudge = $"($CACHE)/nudge"
  if ($nudge | path exists) {
    rm -f $nudge
    let flash = (glyph mic.slash.fill $POINT_SIZE "0xffffa000" nudge --x-shift $X_SHIFT)
    sketchybar --set $env.NAME $"icon.background.image=($flash)"
    sleep 600ms
  }
  let image = (render (call-state) (cached state off))
  sketchybar --set $env.NAME $"icon.background.image=($image)"
}

def main [] {
  match [$env.SENDER ($env.BUTTON? | default left)] {
    ["mouse.clicked" right] => {
      if (zoom-desktop $ZOOM_TOGGLE_OSA) == "none" and (cached call none) != "none" {
        virtual-headset toggle-mute
      }
      # The headset's new state arrives as virtual_headset_changed; Zoom desktop's
      # menu title lags its click, so give it a moment before re-reading.
      sleep 300ms
      sync
    }
    ["mouse.clicked" _] => {
      let x = (try {
        sketchybar --query $env.NAME | from json | get bounding_rects | values | first | get origin.0
      } catch { null })
      if $x == null { virtual-headset panel } else { virtual-headset panel $"($x)" }
    }
    _ => { sync }
  }
}
