# Race two SSH transports for praesidium and exec whichever is fastest.
# Used as the ProxyCommand for `ssh praesidium`.
#
# Path preference is determined by measured latency, not category:
#   - tailscale ping prints its RTT ("in 47ms", "in 1.744s"). We parse
#     the number and compare against TS_FAST_THRESHOLD.
#   - If tailscale RTT < threshold, it's definitively faster than
#     cloudflared can be (cf needs ~4 RTTs of TCP+TLS+HEAD just to
#     respond), so commit immediately.
#   - If tailscale RTT ≥ threshold, the path might be relay/slow-P2P.
#     Race against cloudflared with a grace timer; prefer cf if it
#     arrives, fall back to tailscale otherwise.
#
# Why TS_FAST_THRESHOLD = 150ms:
#   Cloudflared HEAD requires DNS + TCP handshake + TLS handshake +
#   request/response — ~4 RTTs minimum. On a good network with 30ms
#   to nearest CF edge, that's ~120ms floor. Below 150ms, tailscale
#   is unambiguously faster. Above 150ms, cloudflared might beat
#   tailscale's measured path.
#
# Algorithm:
#   - Spawn both probes. Each writes a marker on success:
#       cf.ok       (cloudflared HEAD succeeded)
#       ts-fast.ok  (tailscale ping < threshold)
#       ts-slow.ok  (tailscale ping ≥ threshold)
#   - Poll markers:
#       ts-fast.ok  → win immediately (no cf can be faster)
#       cf.ok       → win (preferred over ts-slow)
#       ts-slow.ok  → start SLOW_GRACE timer; wait for cf to catch up
#       grace expires → use ts-slow (only working option)
#   - Overall timeout caps the wait when nothing succeeds.

const CF_HOSTNAME = "ssh.lalala.casa"
const CF_TEAM = "xorlop.cloudflareaccess.com"
const PROBE_TIMEOUT_SECS = 5
const TS_FAST_THRESHOLD_MS = 150.0
const SLOW_GRACE = 1sec

def main [] {

  # Resolve praesidium's tailnet IP at runtime rather than hardcoding it — the
  # address is assigned by the tailnet and shouldn't live in the repo. If the
  # node is offline `tailscale ip` errors/empties, the ts probe simply fails and
  # cloudflared wins.
  let tailnet_ip = (^tailscale ip -4 praesidium | str trim)

  let tmpdir = (^mktemp -d | str trim)
  let cf_marker = $"($tmpdir)/cf.ok"
  let ts_fast_marker = $"($tmpdir)/ts-fast.ok"
  let ts_slow_marker = $"($tmpdir)/ts-slow.ok"

  let cf_url = $"https://($CF_TEAM)/cdn-cgi/access/login/($CF_HOSTNAME)"

  let cf_job = job spawn {
    let r = do { ^curl --max-time $PROBE_TIMEOUT_SECS -sI -o /dev/null $cf_url } | complete
    if $r.exit_code == 0 {
      try { "ok" | save --force $cf_marker }
    }
  }

  let ts_job = job spawn {
    let timeout_str = $"($PROBE_TIMEOUT_SECS)s"
    let r = do { ^tailscale ping --c 1 --until-direct=false --timeout $timeout_str $tailnet_ip } | complete
    if $r.exit_code == 0 {
      # Parse "in 47ms" or "in 1.744s" from the pong line.
      let matches = $r.stdout | parse --regex 'in (?P<num>[\d.]+)(?P<unit>m?s)\b'
      let latency_ms = if ($matches | length) > 0 {
        let m = $matches | first
        let n = $m.num | into float
        if $m.unit == "ms" { $n } else { $n * 1000.0 }
      } else {
        # Couldn't parse — assume slow (safer than assuming fast).
        99999.0
      }
      if $latency_ms < $TS_FAST_THRESHOLD_MS {
        try { $"($latency_ms)" | save --force $ts_fast_marker }
      } else {
        try { $"($latency_ms)" | save --force $ts_slow_marker }
      }
    }
  }

  let main_deadline = ((date now) + ($PROBE_TIMEOUT_SECS * 1sec) + 2sec)
  mut winner = ""
  mut slow_seen = false
  mut slow_seen_at = (date now) # overwritten when slow path actually appears

  while $winner == "" and ((date now) < $main_deadline) {
    if ($ts_fast_marker | path exists) {
      $winner = "tailnet"
    } else if ($cf_marker | path exists) {
      $winner = "cloudflared"
    } else if ($ts_slow_marker | path exists) {
      if not $slow_seen {
        $slow_seen_at = (date now)
        $slow_seen = true
      }
      if ((date now) - $slow_seen_at) > $SLOW_GRACE {
        $winner = "tailnet"
      } else {
        sleep 50ms
      }
    } else {
      sleep 50ms
    }
  }

  try { job kill $cf_job }
  try { job kill $ts_job }
  rm -rf $tmpdir

  if $winner == "" {
    print -e $"ssh-praesidium-route: both transports unreachable within ($PROBE_TIMEOUT_SECS)s"
    exit 1
  }

  # Exec the winning transport. Nu inherits stdio to the external
  # command, so SSH gets the byte stream directly.
  match $winner {
    "cloudflared" => { ^cloudflared access ssh --hostname $CF_HOSTNAME }
    "tailnet" => { ^nc $tailnet_ip 22 }
  }
}
