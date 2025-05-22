# ~/.config/sketchybar/sketchybarrc.nu
# This is a demo config to showcase some of the most important commands.
# It is meant to be changed and configured, as it is intentionally kept sparse.
# For a (much) more advanced configuration example see my dotfiles:
# https://github.com/FelixKratz/dotfiles

# $CONFIG_DIR is the directory where the currently loaded sketchybarrc is located
let PLUGIN_DIR = "~/.config/sketchybar/plugins"

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
  "icon.font=Maple Mono NF:Normal:24.0",
  "label.font=Maple Mono NF:Normal:14.0",
  "icon.color=0xffffffff",
  "label.color=0xffffffff",
  "icon.padding_left=24",
  "icon.padding_right=2",
  "label.padding_left=4",
  "label.padding_right=4"
]
sketchybar --default ...$default_props

# on top of windows, but under actual MacOS native menu bar
sketchybar --bar "topmost=window"
sketchybar --bar "font_smoothing=on"

##### Adding Left Items #####
# We add some regular items to the left side of the bar, where
# only the properties deviating from the current defaults need to be set

let front_app_props = [
  "label.padding_left=4",
  "label.padding_right=10",
  "icon.background.drawing=on",
  "display=active",
  $"script=($PLUGIN_DIR)/front_app.nu",
  "click_script=open -a 'Mission Control'"
]

(sketchybar --add item front_app left
  --set front_app ...$front_app_props
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
(sketchybar --add item clock right
  --set clock "update_freq=30" $"script=($PLUGIN_DIR)/clock.nu")

# Control Center,BentoBox
(sketchybar --add alias "Control Center,BentoBox" right
  --set "Control Center,BentoBox" "icon.padding_left=0" "padding_left=0" "padding_right=-20"
  "click_script=osascript -e 'tell application \"System Events\" to tell process \"Control Center\" to perform action \"AXPress\" of menu bar item 2 of menu bar 1'")

# Control Center,WiFi
(sketchybar --add alias "Control Center,WiFi" right
  --set "Control Center,WiFi" "icon.padding_left=4" "padding_left=0" "padding_right=-20"
  "click_script=osascript -e 'tell application \"System Events\" to tell process \"Control Center\" to perform action \"AXPress\" of menu bar item 3 of menu bar 1'")

# battery
(sketchybar --add item battery right
  --set battery "update_freq=120" $"script=($PLUGIN_DIR)/battery.nu"
  "click_script=osascript -e 'tell application \"System Events\" to tell process \"Control Center\" to perform action \"AXPress\" of menu bar item 4 of menu bar 1'"
  --subscribe battery system_woke)

# Control Center,Battery
(sketchybar --add alias "Control Center,Battery" right
  --set "Control Center,Battery" "icon.padding_left=4" "padding_left=0"
  "click_script=osascript -e 'tell application \"System Events\" to tell process \"Control Center\" to perform action \"AXPress\" of menu bar item 4 of menu bar 1'")

# volume
(sketchybar --add item volume right
  --set volume $"script=($PLUGIN_DIR)/volume.nu" "icon.padding_left=8" "padding_left=0"
  --subscribe volume volume_change
)

# Twingate,Item-0
(sketchybar --add alias "Twingate,Item-0" right
  --set "Twingate,Item-0" "icon.padding_left=0" "padding_left=0" "padding_right=-20")

##### Force all scripts to run the first time (never do this in a script) #####
sketchybar --update
