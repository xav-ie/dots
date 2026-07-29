{
  openssh,
  tailscale,
  xdg-utils,
  writeNuApplication,
}:
writeNuApplication {
  name = "browse";
  runtimeInputs = [
    openssh
    tailscale
    xdg-utils
  ];
  text = # nu
    ''
      # The IP of the SSH client behind a herdr remote session, or "" if we're
      # local. herdr attaches over SSH but panes run under the long-lived
      # `herdr server`, so SSH_CLIENT isn't in our own env — read it off the
      # per-connection `remote-client-bridge` process herdr spawns per client.
      def herdr-client-ip [] {
        for f in (glob /proc/*/cmdline) {
          let cmd = (try { open --raw $f | decode utf-8 } catch { "" })
          if ($cmd =~ "remote-client-bridge") {
            let pid = ($f | path dirname | path basename)
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

      # Open a URL in *my* browser. Under a herdr remote session the browser
      # lives on the laptop I attached from, so ssh back and `open` it there;
      # otherwise open it locally.
      def main [url: string] {
        let ip = (herdr-client-ip)
        # Attaching through the cloudflared ProxyCommand makes sshd see the
        # client as loopback, so the IP points back at this host instead of my
        # laptop; go over the tailnet instead.
        # ponytail: assumes that client is nox; widen if I attach from more macs.
        let host = if $ip in ["::1" "127.0.0.1"] {
          (^tailscale ip -4 nox | str trim)
        } else { $ip }
        if ($host | is-empty) { ^xdg-open $url } else { ^ssh $host open $url }
      }
    '';
}
