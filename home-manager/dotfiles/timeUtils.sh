#!/usr/bin/env sh
# set -e

time_to_seconds() {
  local time_input="$1"
  local total_seconds=0

  local d=$(echo "$time_input" | grep -oP '\d+(?=d)')
  local h=$(echo "$time_input" | grep -oP '\d+(?=h)')
  local m=$(echo "$time_input" | grep -oP '\d+(?=m)')
  local s=$(echo "$time_input" | grep -oP '\d+(?=s)')

  [ ! -z "$d" ] && total_seconds=$((total_seconds + d * 86400))
  [ ! -z "$h" ] && total_seconds=$((total_seconds + h * 3600))
  [ ! -z "$m" ] && total_seconds=$((total_seconds + m * 60))
  [ ! -z "$s" ] && total_seconds=$((total_seconds + s))

  if [ "$total_seconds" -eq 0 ]; then
    echo "Invalid unit. Use 'd', 'h', 'm', or 's'."
    return 1
  fi

  echo "$total_seconds"
}

remind_me() {
  local time_input="$1"
  local message="$2"
  local seconds=$(time_to_seconds "$time_input")

  if [ $? -eq 1 ]; then
    echo "Failed to convert time."
    return 1
  fi

  # TODO: make this script explicitly depend on notify program
  setsid bash -c "sleep $seconds && notify 'Reminder' '$message'"
}

get_elapsed_time() {
  local pid="$1"
  local start_time=$(awk '{print $22}' /proc/"$pid"/stat)
  local ticks_per_second=$(getconf CLK_TCK)
  local uptime=$(awk '{print $1}' /proc/uptime | cut -d '.' -f 1)
  echo $((uptime - start_time / ticks_per_second))
}

format_time() {
  local total_seconds="$1"
  local days=$((total_seconds / 86400))
  local hours=$(((total_seconds % 86400) / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  [[ $days -gt 0 ]] && printf "${days}d"
  [[ $hours -gt 0 ]] && printf "${hours}h"
  [[ $minutes -gt 0 ]] && printf "${minutes}m"
  printf "${seconds}s"
}

list_reminders() {
  printf "%-10s | %-30s | %-20s\n" "PID" "Message" "Time Remaining"
  printf "%s\n" "---------------------------------------------------------------"
  # IDK if this needs modifications
  pgrep -af "sleep .*notify-send" | while read -r pid cmd; do
    local elapsed_time=$(get_elapsed_time "$pid")
    local sleep_time=$(echo "$cmd" | awk '{print $4}')
    local remaining_time=$((sleep_time - elapsed_time))
    local formatted_time=$(format_time "$remaining_time")
    local message=$(echo "$cmd" | awk -F"'" '{print $4}')
    printf "%-10s | %-30s | %-20s\n" "$pid" "$message" "$formatted_time"
  done
}
