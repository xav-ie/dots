#!/usr/bin/env -S nu --stdin

def main [] {
  let blocked = (rfkill list bluetooth | lines | find "Soft blocked" | str trim | split column ": " | get column2.0 | ansi strip)

  if $blocked == "yes" {
    let result = {
      "text": "<span>󰂲 </span>",
      "tooltip": "Bluetooth disabled\nClick to enable",
      "class": "bluetooth"
    }
    print ($result | to json -r)
  } else {
    let connected = (bluetoothctl devices Connected | lines | parse "Device {mac} {name}" | length)
    let devices = (bluetoothctl devices Connected | lines | parse "Device {mac} {name}" | each { |dev| $"($dev.name)   ($dev.mac)" } | str join "\n")

    if $connected > 0 {
      let tooltip = if ($devices | is-empty) { "Connected devices" } else { $devices }
      let result = {
        "text": "<span> </span>",
        "tooltip": "($tooltip)\nClick to disable",
        "class": "bluetooth"
      }
      print ($result | to json -r)
    } else {
      let result = {
        "text": "<span> </span>",
        "tooltip": "No devices connected\nClick to disable",
        "class": "bluetooth"
      }
      print ($result | to json -r)
    }
  }
}
