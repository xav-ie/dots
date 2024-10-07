#!/bin/sh

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
  exit 0
fi

# if [[ "$CHARGING" != "" ]]; then
#   case "${PERCENTAGE}" in
#     100) ICON="󱈏"
#     ;;
#     9[0-9]) ICON="󰂋"
#     ;;
#     8[0-9]) ICON="󰂊"
#     ;;
#     7[0-9]) ICON="󰢞"
#     ;;
#     6[0-9]) ICON="󰂉"
#     ;;
#     5[0-9]) ICON="󰢝"
#     ;;
#     4[0-9]) ICON="󰂈"
#     ;;
#     3[0-9]) ICON="󰂇"
#     ;;
#     2[0-9]) ICON="󰂆"
#     ;;
#     1[0-9]) ICON="󰢜"
#     ;;
#     *) ICON="󰢟"
#   esac
#   ICON_SIZE=25.0
#   ICON_PADDING_RIGHT=0
# else
#   case "${PERCENTAGE}" in
#     100) ICON="󰁹"
#     ;;
#     9[0-9]) ICON="󰂂"
#     ;;
#     8[0-9]) ICON="󰂁"
#     ;;
#     7[0-9]) ICON="󰂀"
#     ;;
#     6[0-9]) ICON="󰁿"
#     ;;
#     5[0-9]) ICON="󰁾"
#     ;;
#     4[0-9]) ICON="󰁽"
#     ;;
#     3[0-9]) ICON="󰁼"
#     ;;
#     2[0-9]) ICON="󰁻"
#     ;;
#     1[0-9]) ICON="󰁺"
#     ;;
#     *) ICON="󰂎"
#   esac
#   ICON_SIZE=14.0
#   ICON_PADDING_RIGHT=7
# fi

# The item invoking this script (name $NAME) will get its icon and label
# updated with the current battery status
sketchybar --set "$NAME" icon.padding_left=0 icon.padding_right=4 label="${PERCENTAGE}%"
