# The $NAME variable is passed from sketchybar and holds the name of
# the item invoking this script:
# https://felixkratz.github.io/SketchyBar/config/events#events-and-scripting
def main [] {
  let hour = (date now | format date "%-I" | into int)

  let icon = match $hour {
    12 => "󱑖"
    1 => "󱑋"
    2 => "󱑌"
    3 => "󱑍"
    4 => "󱑎"
    5 => "󱑏"
    6 => "󱑐"
    7 => "󱑑"
    8 => "󱑒"
    9 => "󱑓"
    10 => "󱑔"
    11 => "󱑕"
    _ => "" # Default case for any unexpected value
  }

  let label = (date now | format date "%a %b %-d %-I:%M%p")

  sketchybar --set $"($env.NAME)" $"icon=($icon)" $"label=($label)"
}
