#!/usr/bin/env nu --stdin

source "~/.config/sketchybar/nix-settings.nu"
let PLUGIN_DIR = "plugins"

##### Bar Appearance #####
# Configuring the general appearance of the bar.
# These are only some of the options available. For all options see:
# https://felixkratz.github.io/SketchyBar/config/bar
# If you are looking for other colors, see the color picker:
# https://felixkratz.github.io/SketchyBar/config/tricks#color-picker

sketchybar --bar "position=top" "height=32" "blur_radius=30" "color=0x90000000"

##### Changing Defaults #####
# We now change some default values, which are applied to all further items.
# For a full list of all available item properties see:
# https://felixkratz.github.io/SketchyBar/config/items

let default_props = [
  "padding_left=-10",
  "padding_right=-10",
  $"icon.font=(get_icon_font)",
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

##### Adding Left Items #####
# We add some regular items to the left side of the bar, where
# only the properties deviating from the current defaults need to be set

(sketchybar --add item front_app left
  --set front_app $"script=($PLUGIN_DIR)/front_app.nu"
  --subscribe front_app front_app_switched)

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
(sketchybar --add event clock_hover)
(sketchybar --add item clock right --set clock $"script=($PLUGIN_DIR)/clock.nu")
(sketchybar --add item clock_icon right --set clock_icon $"script=($PLUGIN_DIR)/clock_icon.nu")

# wifi
(sketchybar --add item wifi_background right --set wifi_background $"script=($PLUGIN_DIR)/wifi_background.nu")
(sketchybar --add alias "Control Center,WiFi" right
  --set "Control Center,WiFi" $"script=($PLUGIN_DIR)/wifi.nu")

# control center
(sketchybar --add item control_center right
  --set control_center $"script=($PLUGIN_DIR)/control_center.nu")

(sketchybar --add event battery_change)
(sketchybar --add event battery_hover)
# battery
(sketchybar --add item battery right
  --set battery $"script=($PLUGIN_DIR)/battery.nu")
# Control Center,Battery
(sketchybar --add alias "Control Center,Battery" right
  --set "Control Center,Battery" $"script=($PLUGIN_DIR)/battery_icon.nu")

# volume
(sketchybar --add event volume_hover)
(sketchybar --add item volume right
  --set volume $"script=($PLUGIN_DIR)/volume.nu"
  --subscribe volume volume_change)
(sketchybar --add item volume_icon right
  --set volume_icon $"script=($PLUGIN_DIR)/volume_icon.nu"
  --subscribe volume_icon volume_change)

##### Force all scripts to run the first time (never do this in a script) #####
sketchybar --update
