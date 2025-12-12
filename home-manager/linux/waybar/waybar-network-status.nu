#!/usr/bin/env -S nu --stdin

def main [] {
  # Check ethernet first (enp3s0)
  let eth_state = (open /sys/class/net/enp3s0/operstate | str trim)
  if $eth_state == "up" {
    let eth_ip = (ip -4 -o addr show enp3s0 | parse -r 'inet (?P<ip>\S+)' | get 0.ip)
    let result = {
      "text": $"<span>󰈀 </span>",
      "tooltip": $"Ethernet: ($eth_ip)",
      "class": "ethernet"
    }
    print ($result | to json -r)
    exit 0
  }

  # Fall back to wifi (wlp4s0)
  let wifi_state = (open /sys/class/net/wlp4s0/operstate | str trim)
  if $wifi_state == "up" {
    let essid = (iwgetid -r | str trim)
    let signal = try { open /proc/net/wireless | lines | last | split row -r '\s+' | get 3 | str replace "." "" | into int } catch { 0 }
    let result = {
      "text": "<span> </span>($essid)",
      "tooltip": $"($essid) \(($signal)%\) ",
      "class": "wifi"
    }
    print ($result | to json -r)
    exit 0
  }

  # Disconnected
  let result = {
    "text": "<span>󰖪 </span>No Network",
    "tooltip": "No network connection",
    "class": "disconnected"
  }
  print ($result | to json -r)
  exit 0
}
