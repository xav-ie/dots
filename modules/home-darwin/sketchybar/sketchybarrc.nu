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
  "padding_left=-10",
  "padding_right=-10",
  # No icon.font: every bar icon is now a PNG rendered by `sketchybar-icons`
  # (battery/wifi/clock/control_center/volume), so the mono Nerd icon font is no
  # longer needed. Labels still use the tabular font below.
  $"label.font=(get_label_font)",
  "icon.color=0xffffffff",
  "label.color=0xffffffff",
  "icon.padding_left=24",
  "icon.padding_right=2",
  "label.padding_left=4",
  "label.padding_right=4"
  "label.background.height=24"
  "icon.background.height=24"
  "label.background.corner_radius=6"
  "icon.background.corner_radius=6"
]
sketchybar --default ...$default_props

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

# clock
(sketchybar --add item clock right
  --set clock $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/clock.nu"
  --subscribe clock mouse.entered mouse.exited)
(sketchybar --add item clock_icon right
  --set clock_icon $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/clock_icon.nu"
  --subscribe clock_icon mouse.entered mouse.exited)

# wifi
# Native icon rendered by `sketchybar-icons` (SF Symbol -> PNG via CoreWLAN
# signal), replacing the old `Control Center,WiFi` alias that screen-recorded the
# menu bar. `network_change` is the com.apple.system.config.network_change
# distributed notification (instant connect/disconnect); `update_freq` refreshes
# signal bars. The item paints its own background as the hover highlight, so no
# separate wifi_background item is needed.
(sketchybar --add event network_change com.apple.system.config.network_change)
(sketchybar --add item wifi right
  --set wifi $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/wifi.nu" update_freq=30
  --subscribe wifi network_change mouse.entered mouse.exited)

# control center
(sketchybar --add item control_center right
  --set control_center $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/control_center.nu"
  --subscribe control_center mouse.entered mouse.exited)

(sketchybar --add event battery_change)
# battery
(sketchybar --add item battery right
  --set battery $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/battery.nu"
  --subscribe battery battery_change mouse.entered mouse.exited)
# battery icon: native SF Symbol rendered by `sketchybar-icons`, replacing the
# old `Control Center,Battery` alias that screen-recorded the menu bar.
(sketchybar --add item battery_icon right
  --set battery_icon $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/battery_icon.nu"
  --subscribe battery_icon battery_change mouse.entered mouse.exited)

# volume
(sketchybar --add item volume right
  --set volume $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/volume.nu"
  --subscribe volume volume_change mouse.entered mouse.exited)
# volume_icon does NOT subscribe to volume_change: volume.nu owns the icon image
# and drives it in lockstep with the number tween (see volume.nu). It still needs
# mouse events for the shared hover highlight.
(sketchybar --add item volume_icon right
  --set volume_icon $"script=sketchybar-hover --plugin ($PLUGIN_DIR)/volume_icon.nu"
  --subscribe volume_icon mouse.entered mouse.exited)

##### Force all scripts to run the first time (never do this in a script) #####
sketchybar --update
