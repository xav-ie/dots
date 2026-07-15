#!/usr/bin/env nu --stdin

# Zoom mute indicator. Shows a mic glyph ONLY while a Zoom meeting is active:
# red `mic.slash.fill` when muted, white `mic.fill` when live. State is READ from
# Zoom's own "Meeting" menu over the Accessibility API (no private APIs) and
# toggled by clicking that same menu item — so it stays in sync with whatever you
# do in Zoom itself.
#
# Event-driven only — NO update_freq, it never polls. State refreshes on:
#   forced             -> init
#   front_app_switched -> you switched apps; also decides show/hide
#   mouse.clicked      -> toggle mute (see the handler)
#
# Wrapped in `sketchybar-hover` like the other items: that daemon owns the hover
# highlight, painting this item's own background.color on mouse.entered/exited
# (see the `zoom_mute` -> bg_only entry in sketchybar-hoverd's item map). Hover no
# longer re-reads Zoom, so an external mute change (muting in Zoom's own UI) is
# reflected on the next app switch rather than on hover.
#
# Requires Accessibility permission for whatever ends up driving System Events
# (the sketchybar launchd agent / osascript). Without it, read-state always
# returns "not-in-meeting" and the icon simply never appears.
# NOTE: the "Mute/Unmute audio" menu labels are English-only.

const CACHE_DIR = "~/.cache/sketchybar" | path expand
const POINT_SIZE = 12
# Icon button width (points). --min-width pads the rendered PNG to this same width
# so the glyph is CENTERED and fills the slot; without it the narrow glyph
# left-aligns with slack and looks off-centre. Must equal icon.width in props.
const ICON_WIDTH = 24
# Optical nudge (points, +right) baked into the PNG. mic.slash's diagonal slash
# makes a geometrically-centred glyph read as left-leaning; a small +shift recentres it.
const X_SHIFT = 0.5
# Transparent starting background; the sketchybar-hover daemon animates from here
# to its hover colour and back.
const CLEAR_COLOR = "0x00000000"

# Zoom's "Meeting" menu has one audio item whose title flips: "Unmute audio"
# (currently muted) vs "Mute audio" (currently live). Absent/erroring => not in a
# meeting. Scan by name, not index, so Zoom reordering the menu can't break it.
const READ_OSA = '
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
  return "not-in-meeting"
end tell'

# Click the audio menu item AND report the state it was in BEFORE the click, in
# one atomic osascript. The pre-click title is the reliable truth (Zoom only
# delays refreshing the title AFTER a programmatic click), so the caller derives
# the new state as its opposite instead of re-reading (which would race the
# delayed refresh). Returns "muted"/"unmuted" (the BEFORE state) or "not-in-meeting".
const TOGGLE_OSA = '
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
  return "not-in-meeting"
end tell'

def read-state [] {
  osascript -e $READ_OSA | str trim
}

# Toggle mute; returns the state it was in BEFORE the click ("muted"/"unmuted"),
# or "not-in-meeting". The new state is the opposite (see the click handler).
def toggle [] {
  osascript -e $TOGGLE_OSA | str trim
}

# Render (or reuse) the glyph PNG for a mute state; return its path. Filename is
# keyed by state + size so sketchybar reloads on change and skips re-rendering
# when unchanged.
def render [state: string] {
  # muted = white mic.slash (safe/quiet); unmuted = red mic (you're LIVE). The
  # colour is passed as a two-entry palette (both the same) so multi-layer glyphs
  # like mic.slash render FLAT in one colour instead of SF's two-tone hierarchical
  # look. key includes the colour so old two-tone/red-muted PNGs get busted.
  let spec = if $state == "muted" {
    {sym: "mic.slash.fill", color: "0xffffffff", key: "muted-w"}
  } else {
    {sym: "mic.fill", color: "0xffff453a", key: "unmuted-r"}
  }
  let out = $"($CACHE_DIR)/zoom-($spec.key)-($POINT_SIZE)-w($ICON_WIDTH)-x($X_SHIFT).png"
  if not ($out | path exists) {
    sketchybar-icons symbol --symbol $spec.sym --point-size $POINT_SIZE --scale 2 --min-width $ICON_WIDTH --x-shift $X_SHIFT --palette $"($spec.color),($spec.color)" --out $out | ignore
  }
  $out
}

# Show the glyph for the current mute state, or hide the whole item when there's
# no active meeting.
def sync [] {
  let state = (read-state)
  if $state == "not-in-meeting" {
    sketchybar --set $env.NAME drawing=off
  } else {
    let out = (render $state)
    sketchybar --set $env.NAME drawing=on $"icon.background.image=($out)"
  }
}

def main [] {

  # Static geometry, mirroring wifi.nu so the button lines up with its neighbours.
  let props = [
    "icon.background.drawing=on"
    "icon.background.image.scale=0.5"
    $"icon.width=($ICON_WIDTH)"
    "icon.padding_left=0"
    "icon.padding_right=0"
    "label.drawing=off"
    "background.height=24"
    "background.corner_radius=6"
    "background.drawing=on"
    $"background.color=($CLEAR_COLOR)"
    "padding_left=0"
    # Butt-joint against the volume group. The volume number's background reaches
    # padding_left=-28 while the speaker (volume_icon) is only 24 wide, so the
    # volume bg's left edge pokes ~a few px left of the speaker, into us. 3 is the
    # measured value where our hover box exactly meets it (seam=0px) — not gapping
    # (4) nor overlapping (<3).
    "padding_right=3"
  ]

  match $env.SENDER {
    "forced" => {
      sketchybar --set $env.NAME ...$props
      sync
    }
    "front_app_switched" => { sync }
    "mouse.clicked" => {
      # toggle clicks AND returns the reliable BEFORE state; the new state is its
      # opposite, set directly — no post-click re-read to race Zoom's delayed title
      # refresh, and nothing slower than the single click call.
      let new = match (toggle) {
        muted => "unmuted"
        unmuted => "muted"
        _ => null
      }
      if $new == null {
        sync
      } else {
        sketchybar --set $env.NAME drawing=on $"icon.background.image=(render $new)"
      }
    }
    _ => { }
  }
}
