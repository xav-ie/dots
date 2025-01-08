#!/bin/sh

# The $NAME variable is passed from sketchybar and holds the name of
# the item invoking this script:
# https://felixkratz.github.io/SketchyBar/config/events#events-and-scripting

HOUR=$(date +%-I)

case "$HOUR" in
12)
  ICON="󱑖"
  ;;
1)
  ICON="󱑋"
  ;;
2)
  ICON="󱑌"
  ;;
3)
  ICON="󱑍"
  ;;
4)
  ICON="󱑎"
  ;;
5)
  ICON="󱑏"
  ;;
6)
  ICON="󱑐"
  ;;
7)
  ICON="󱑑"
  ;;
8)
  ICON="󱑒"
  ;;
9)
  ICON="󱑓"
  ;;
10)
  ICON="󱑔"
  ;;
11)
  ICON="󱑕"
  ;;
*)
  ICON=""
  ;;
esac

sketchybar --set "$NAME" icon="$ICON" label="$(date '+%a %b %-d %-I:%M%p')"
