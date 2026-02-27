#!/usr/bin/env -S nu --no-config-file --stdin

def get-bluetooth-status [] {
  let blocked = (rfkill list bluetooth | lines | find "Soft blocked" | str trim | split column ": " | get column2.0 | ansi strip)

  if $blocked == "yes" {
    {
      "text": "<span>󰂲 </span>",
      "tooltip": "Bluetooth disabled\nClick to enable",
      "class": "bluetooth"
    } | to json -r
  } else {
    let connected = (bluetoothctl devices Connected | lines | parse "Device {mac} {name}" | length)
    let devices = (bluetoothctl devices Connected | lines | parse "Device {mac} {name}" | each { |dev| $"($dev.name)   ($dev.mac)" } | str join "\n")

    if $connected > 0 {
      let tooltip = if ($devices | is-empty) { "Connected devices" } else { $devices }
      {
        "text": "<span> </span>",
        "tooltip": $"($tooltip)\nClick to disable",
        "class": "bluetooth"
      } | to json -r
    } else {
      {
        "text": "<span> </span>",
        "tooltip": "No devices connected\nClick to disable",
        "class": "bluetooth"
      } | to json -r
    }
  }
}

let prev_file = (mktemp -t waybar-bluetooth-XXXX)

# Print initial status
let status = (get-bluetooth-status)
print $status
$status | save -f $prev_file

# Poll on a relaxed interval. BlueZ passive scanning still emits BLE advertisement
# signals over D-Bus (~60/sec), making dbus-monitor too CPU-heavy. 5s polling is
# fine since bluetooth status changes infrequently.
loop {
  sleep 5sec
  let status = (get-bluetooth-status)
  let prev = (open $prev_file | str trim)
  if $status != $prev {
    print $status
    $status | save -f $prev_file
  }
}
