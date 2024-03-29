#!/usr/bin/env sh

# 1. Check if slack already running
slack_running=$(pgrep slack)

# 2. If not running, start
if [ -z "$slack_running" ]; then
  slack
fi

# 3. TODO: add some calendaring/pomo thing here... or maybe have manual invocation solution
