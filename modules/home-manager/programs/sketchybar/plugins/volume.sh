#!/bin/sh

# The volume_change event supplies a $INFO variable in which the current volume
# percentage is passed to the script.

if [ "$SENDER" = "volume_change" ]; then
  VOLUME="$INFO"

  case "$VOLUME" in
    [6-9][0-9]|100) ICON="󰕾" ICON_SIZE=20.0 ICON_PADDING_RIGHT=0
    ;;
    [3-5][0-9]) ICON="󰖀" ICON_SIZE=16.0 ICON_PADDING_RIGHT=2
    ;;
    [1-9]|[1-2][0-9]) ICON="󰕿" ICON_SIZE=10.0 ICON_PADDING_RIGHT=6
    ;;
    *) ICON="󰖁" ICON_SIZE=20.0 ICON_PADDING_RIGHT=0
  esac

  sketchybar --set "$NAME" icon="$ICON" icon.font.size=$ICON_SIZE icon.padding_right=$ICON_PADDING_RIGHT label="$VOLUME%"
fi
