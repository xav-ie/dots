#!/usr/bin/env sh

# 1. Check if zoom meeting running
zoom_running=$(hyprctl clients | grep "Zoom Meeting")

# 2. If not running, kill it with pkill
if [ "$zoom_running" = "" ]; then
  pkill zoom

  # 3. Kill slack, too
  pkill slack
fi
