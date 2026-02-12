#!/usr/bin/env -S nu --no-config-file --stdin

def get-network-status [] {
  let eth_state = (open /sys/class/net/enp3s0/operstate | str trim)
  if $eth_state == "up" {
    let eth_ip = (ip -4 -o addr show enp3s0 | parse -r 'inet (?P<ip>\S+)' | get 0.ip)
    {
      "text": $"<span>󰈀 </span>",
      "tooltip": $"Ethernet: ($eth_ip)",
      "class": "ethernet"
    } | to json -r
  } else {
    let wifi_state = (open /sys/class/net/wlp4s0/operstate | str trim)
    if $wifi_state == "up" {
      let essid = (iwgetid -r | str trim)
      let signal = try { open /proc/net/wireless | lines | last | split row -r '\s+' | get 3 | str replace "." "" | into int } catch { 0 }
      {
        "text": $"<span> </span>($essid)",
        "tooltip": $"($essid) \(($signal)%\) ",
        "class": "wifi"
      } | to json -r
    } else {
      {
        "text": "<span>󰖪 </span>No Network",
        "tooltip": "No network connection",
        "class": "disconnected"
      } | to json -r
    }
  }
}

let prev_file = (mktemp -t)

# Print initial status
let status = (get-network-status)
print $status
$status | save -f $prev_file

# Listen for network link/address changes
ip monitor link address | lines | each { |_|
  let status = (get-network-status)
  let prev = (open $prev_file | str trim)
  if $status != $prev {
    print $status
    $status | save -f $prev_file
  }
}
