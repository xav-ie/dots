#!/usr/bin/env nu --stdin

source "~/.config/sketchybar/nix-settings.nu"
let PLUGIN_DIR = "plugins"

##### Bar Appearance #####
# Configuring the general appearance of the bar.
# These are only some of the options available. For all options see:
# https://felixkratz.github.io/SketchyBar/config/bar
# If you are looking for other colors, see the color picker:
# https://felixkratz.github.io/SketchyBar/config/tricks#color-picker

sketchybar --bar "position=top" $"height=(get_bar_height)" "blur_radius=30" "color=0x90000000"

##### Changing Defaults #####
# We now change some default values, which are applied to all further items.
# For a full list of all available item properties see:
# https://felixkratz.github.io/SketchyBar/config/items

let default_props = [
  "padding_left=-10"
  "padding_right=-10"
  # No icon.font: every bar icon is now a PNG rendered by `sketchybar-icons`
  # (battery/wifi/clock/control_center/volume), so the mono Nerd icon font is no
  # longer needed. Labels still use the tabular font below.
  $"label.font=(get_label_font)"
  "icon.color=0xffffffff"
  "label.color=0xffffffff"
  "icon.padding_left=24"
  "icon.padding_right=2"
  "label.padding_left=4"
  "label.padding_right=4"
  "label.background.height=24"
  "icon.background.height=24"
  "label.background.corner_radius=6"
  "icon.background.corner_radius=6"
]
sketchybar --default ...$default_props

# ─── Tiling primitives ───────────────────────────────────────────────────────
# Every bar item's on-screen footprint must abut its neighbours with NO gap and
# NO overlap, so hover is smooth and there are no dead zones. These two helpers
# make that hold BY CONSTRUCTION: ALL geometry (padding / width / background
# drawing / heights) lives here, so the per-item plugins set only CONTENT (the
# glyph image + the number). Verify with `sb-check-tiling`.

# A single icon button (no label). Footprint == `width` == the icon.background
# highlight box; every padding is zeroed so the footprint is exactly `width`.
# `--extra` carries any NON-geometry per-item props (e.g. click_script) or, for a
# `bg_only` item like wifi, its own `background.*` highlight props (which re-enable
# the item background this primitive turns off by default).
def sb-icon-item [
  name: string
  position: string
  width: int
  script: string
  subs: list<string>
  --extra: list<string> = []
] {
  (sketchybar --add item $name $position
    --set $name $"script=($script)"
      "padding_left=0" "padding_right=0"
      $"icon.width=($width)" "icon.padding_left=0" "icon.padding_right=0"
      "icon.background.drawing=on" "icon.background.image.scale=0.5"
      "background.drawing=off"
      "label=" "label.width=0" "label.padding_left=0" "label.padding_right=0"
      ...$extra
    --subscribe $name ...$subs)
}

# An icon+label cluster: a `<name>_icon` glyph plus a `<name>` label that share
# ONE hover highlight. ENFORCES the tiling invariant zone == pull == icon_w:
#   <name>      label.padding_left =  icon_w   (reserved zone the glyph sits in)
#   <name>      padding_left       = -icon_w   (pull the label back over the glyph)
#   <name>_icon icon.width         =  icon_w   (glyph exactly fills the zone)
# so the footprint is exactly [glyph-left .. number-right] with NO overhang past
# the glyph. That overhang (label.padding_left 28 vs a 24px icon) was the hidden
# 4px that made hidewin overlap the volume icon; enforcing equality here fixes it
# at the source. Label is added FIRST (rightmost) and the glyph SECOND (to its
# left), matching the existing right-item visual order (glyph left of number).
# `label_w` fixes the number box (0 = hug the text). `--right-pad` is the only
# inter-item gap knob. `--label-extra`/`--icon-extra` carry non-geometry props
# (click_script, label.align, update_freq).
def sb-cluster [
  name: string
  position: string
  icon_w: int
  label_w: int
  icon_script: string
  icon_subs: list<string>
  label_script: string
  label_subs: list<string>
  --right-pad: int = 0
  --label-extra: list<string> = []
  --icon-extra: list<string> = []
] {
  let label_width = (if $label_w > 0 { [$"label.width=($label_w)"] } else { [] })
  (sketchybar --add item $name $position
    --set $name $"script=($label_script)"
      $"padding_left=(-1 * $icon_w)" $"padding_right=($right_pad)"
      $"label.padding_left=($icon_w)" "label.padding_right=4"
      "icon.width=0" "icon.padding_left=0" "icon.padding_right=0"
      ...$label_width
      ...$label_extra
    --subscribe $name ...$label_subs)
  (sketchybar --add item $"($name)_icon" $position
    --set $"($name)_icon" $"script=($icon_script)"
      "padding_left=0" "padding_right=0"
      $"icon.width=($icon_w)" "icon.padding_left=0" "icon.padding_right=0"
      "icon.background.drawing=on" "icon.background.image.scale=0.5"
      "label=" "label.width=0" "label.padding_left=0" "label.padding_right=0"
      ...$icon_extra
    --subscribe $"($name)_icon" ...$icon_subs)
}

# on top of windows, but under actual MacOS native menu bar
sketchybar --bar "topmost=window"
sketchybar --bar "font_smoothing=on"

# Hover state for every interactive item is owned by `sketchybar-hoverd` (a
# launchd-managed daemon). Items invoke `sketchybar-hover --plugin <path>` as
# their script: mouse events get forwarded to the daemon over a Unix socket;
# everything else (forced/data updates) execs the underlying nu plugin.

##### Adding Left Items #####
# We add some regular items to the left side of the bar, where
# only the properties deviating from the current defaults need to be set
(sketchybar --add item front_app left
  --set front_app $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/front_app.nu"
  $"label.font=(get_app_font)"
  --subscribe front_app front_app_switched mouse.entered mouse.exited mouse.exited.global)

##### Adding Right Items #####
# In the same way as the left items we can add items to the right side.
# Additional position (e.g. center) are available, see:
# https://felixkratz.github.io/SketchyBar/config/items#adding-items-to-sketchybar

# Some items refresh on a fixed cycle, e.g. the clock runs its script once
# every 30s. Other items respond to events they subscribe to, e.g. the
# volume.nu script is only executed once an actual change in system audio
# volume is registered. More info about the event system can be found here:
# https://felixkratz.github.io/SketchyBar/config/events

# clock — icon+label cluster (sb-cluster), identical structure to volume/battery.
# icon_w=24 == the clock-face zone (the 18px face is centred in it via clock_icon's
# --min-width, leaving a small gap to the time). label_w=0 → the time string hugs
# its own width (it's variable: day/date/12h). The tick is driven by update_freq
# (the `routine` sender), passed to both sub-items via --*-extra. Highlight is ONE
# shared label.background over [face + time] (clock -> label_only in
# sketchybar-hoverd, matching volume/battery). click opens Control Center > Clock.
sb-cluster clock right 24 0 (
  $"sketchybar-hover --plugin ($PLUGIN_DIR)/clock_icon.nu"
) [mouse.entered mouse.exited] (
  $"sketchybar-hover --plugin ($PLUGIN_DIR)/clock.nu"
) [mouse.entered mouse.exited] --label-extra [
  "update_freq=30"
  "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Clock\""
] --icon-extra [
  "update_freq=30"
  "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Clock\""
]

# wifi — single icon (sb-icon-item). Native icon rendered by `sketchybar-icons`
# (SF Symbol -> PNG via CoreWLAN signal). `wifi_change` is emitted by the
# sketchybar-wifi daemon straight off CoreWLAN events — that's what makes
# connect/disconnect/signal instant. `network_change` (the
# com.apple.system.config.network_change distributed notification) is kept ONLY
# for route changes, i.e. hotspot tether on/off, which CoreWLAN can't see; it is
# posted by configd once the whole stack settles, so it is seconds late on its
# own. NO `update_freq` — both sources are push, so nothing here polls.
# wifi is `bg_only`:
# the hover highlight is the item's OWN full-footprint background, so --extra
# re-enables it (the primitive turns background.drawing off by default). NO
# background.padding — under the tiling primitives every item already abuts, so
# the old -1px seam-closer now just overlaps control_center's highlight.
# click_script opens Control Center > Wi-Fi.
(sketchybar --add event network_change com.apple.system.config.network_change)
(sketchybar --add event wifi_change)
sb-icon-item wifi right 26 $"sketchybar-hover --plugin ($PLUGIN_DIR)/wifi.nu" [wifi_change network_change mouse.entered mouse.exited] --extra [
  "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Wi-Fi\""
  "background.height=24"
  "background.corner_radius=6"
  "background.drawing=on"
  "background.color=0x00000000"
]

# control center — single icon (sb-icon-item, icon_only highlight).
sb-icon-item control_center right 26 $"sketchybar-hover --plugin ($PLUGIN_DIR)/control_center.nu" [mouse.entered mouse.exited] --extra [
  "click_script=$HOME/.config/sketchybar/select_control_center.nu \"Control Center\""
]

# battery — icon+label cluster (sb-cluster). icon_w=36 == the rendered battery
# glyph width, so zone==pull==36 (was 40, the 4px overhang). label_w=0 → the %
# hugs the text. battery_change is emitted by the sketchybar-battery daemon.
(sketchybar --add event battery_change)
sb-cluster battery right 36 0 (
  $"sketchybar-hover --plugin ($PLUGIN_DIR)/battery_icon.nu"
) [battery_change mouse.entered mouse.exited] (
  $"sketchybar-hover --plugin ($PLUGIN_DIR)/battery.nu"
) [battery_change mouse.entered mouse.exited] --label-extra ["click_script=$HOME/.config/sketchybar/select_control_center.nu \"Battery\""] --icon-extra ["click_script=$HOME/.config/sketchybar/select_control_center.nu \"Battery\""]

# volume — icon+label cluster (sb-cluster). icon_w=24 == the speaker glyph width,
# so zone==pull==24 (was 28, the 4px overhang that overlapped hidewin). label_w=61
# fixes the number box (volume.nu re-sizes it per digit-count via an animated
# tween). volume_icon does NOT subscribe volume_change — volume.nu owns the icon
# image and drives it in lockstep with the number tween — but still needs mouse
# events for the shared hover highlight.
sb-cluster volume right 24 61 (
  $"sketchybar-hover --plugin ($PLUGIN_DIR)/volume_icon.nu"
) [mouse.entered mouse.exited] (
  $"sketchybar-hover --plugin ($PLUGIN_DIR)/volume.nu"
) [volume_change mouse.entered mouse.exited] --label-extra [
  "label.align=right"
  "click_script=$HOME/.config/sketchybar/open_volume_control.scpt"
] --icon-extra ["click_script=$HOME/.config/sketchybar/open_volume_control.scpt"]

# hidewin — single icon (sb-icon-item, icon_only). Screen-capture hiding toggle
# (packages/hidewin-bar), placed to the LEFT of the volume icon (right items add
# right-to-left). Its plugin owns the icon image (white = Normal, orange =
# Screenshare Mode); `hidewin_mode` is bound to the com.x.hidewin.mode-changed
# notification the agent posts. mouse.clicked opens the panel.
(sketchybar --add event hidewin_mode com.x.hidewin.mode-changed)
(sb-icon-item
  hidewin
  right
  26
  $"sketchybar-hover --plugin ($PLUGIN_DIR)/hidewin.nu"
  [hidewin_mode mouse.entered mouse.exited mouse.clicked]
)

# zoom mute — shows ONLY during an active Zoom meeting: white mic.slash when
# muted, red mic when LIVE. State is read/toggled from Zoom's own "Meeting" menu
# over Accessibility (see plugins/zoom_mute.nu). Wrapped in sketchybar-hover like
# the other items, so the hover daemon owns the highlight (zoom_mute -> bg_only in
# its map); mouse.entered/exited go to the daemon, everything else (forced,
# front_app_switched, mouse.clicked) execs the plugin. front_app_switched drives
# show/hide, so there's no polling. Added LAST among right items so it sits
# left-most in the right cluster (left of the volume icon). Hidden until a meeting.
(sketchybar --add item zoom_mute right
  --set zoom_mute $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/zoom_mute.nu" drawing=off
  --subscribe zoom_mute front_app_switched mouse.entered mouse.exited mouse.clicked)

##### Force all scripts to run the first time (never do this in a script) #####
sketchybar --update
