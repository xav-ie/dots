#!/bin/sh

# The volume_change event supplies a $INFO variable in which the current volume
# percentage is passed to the script.

if [ "$SENDER" = "volume_change" ]; then
  VOLUME="$INFO"

  case "$VOLUME" in
  7[5-9] | 8[0-9] | 9[0-9] | 100)
    ICON="􀊩" ICON_SIZE=14.0 ICON_PADDING_RIGHT=0 # three bars
    ;;
  5[0-9] | 6[0-9] | 7[0-4])
    ICON="􀊧" ICON_SIZE=14.0 ICON_PADDING_RIGHT=3 # two bars
    ;;
  2[5-9] | 3[0-9] | 4[0-9])
    ICON="􀊥" ICON_SIZE=14.0 ICON_PADDING_RIGHT=6 # one bar
    ;;
  [1-9] | 1[0-9] | 2[0-4])
    ICON="􀊡" ICON_SIZE=14.0 ICON_PADDING_RIGHT=10 # no bars
    ;;
  0)
    ICON="􀊣" ICON_SIZE=14.0 ICON_PADDING_RIGHT=6 # muted
    ;;
  esac

  sketchybar --set "$NAME" icon="$ICON" icon.font.size="$ICON_SIZE" icon.padding_right="$ICON_PADDING_RIGHT" label="$VOLUME%"
fi
