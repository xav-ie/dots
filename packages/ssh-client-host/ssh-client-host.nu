# Print the host I'm driving this box from, or "" if I'm local. A plain SSH
# login carries SSH_CLIENT in our own env. herdr attaches over SSH but panes
# run under the long-lived `herdr server`, so read SSH_CLIENT off the
# per-connection `remote-client-bridge` process herdr spawns per client.
def herdr-client-ip [] {
  for f in (glob /proc/*/cmdline) {
    let cmd = (
      try {
        open --raw $f | decode utf-8
      } catch { "" }
    )
    if $cmd =~ "remote-client-bridge" {
      let pid = $f | path dirname | path basename
      let ip = (try { open --raw $"/proc/($pid)/environ" | decode utf-8 } catch { "" }
        | split row "\u{0}"
        | where {|e| $e | str starts-with "SSH_CLIENT=" }
        | get 0?
        | default ""
        | str replace "SSH_CLIENT=" ""
        | split row " "
        | get 0?
        | default "")
      if ($ip | is-not-empty) { return $ip }
    }
  }
  ""
}

def main [] {
  let ip = (
    $env.SSH_CLIENT?
    | default ""
    | split row " "
    | get 0
  )
  let ip = if ($ip | is-empty) { herdr-client-ip } else { $ip }
  # Attaching through the cloudflared ProxyCommand makes sshd see the client
  # as loopback, so the IP points back at this host instead of my laptop; go
  # over the tailnet instead.
  # ponytail: assumes that client is nox; widen if I attach from more macs.
  if $ip in ["::1" "127.0.0.1"] {
    "nox"
  } else { $ip }
}
