#!/usr/bin/env nu --stdin

# Native Wi-Fi icon. Reads live signal via CoreWLAN (`sketchybar-icons wifi`,
# which needs no Location permission because it never touches the SSID) and
# renders Apple's own `wifi` SF Symbol at a variable value so the arcs fill by
# signal strength — exactly like Control Center. Replaces the old
# `Control Center,WiFi` alias, which mirrored the real menu-bar item by
# continuously screen-recording it.
#
# Driven by `wifi_change`, emitted by the sketchybar-wifi daemon straight off
# CoreWLAN events (the same ones Control Center listens to) — that's what makes
# this instant — and again once configd settles routes/flags after any network
# change, which is what catches hotspot tether on/off. All push — nothing
# polls, so there is deliberately no `update_freq` on the item.

const CACHE_DIR = "~/.cache/sketchybar" | path expand
# On-screen icon height in px (rendered at 2x, drawn at background.image.scale
# 0.5). Sized to match the neighbouring control_center / clock glyphs. Included
# in the cache filename so bumping it busts stale PNGs.
const POINT_SIZE = 14
# Pad the rendered PNG to this on-screen width (points) with the glyph centred,
# so the hover-highlight button is a touch narrower than control_center. Paired
# with icon.width below (which sketchybar left-aligns the image within).
const MIN_WIDTH = 26

# Map the arc count `sketchybar-icons` reports (0..3) to a variableValue the
# `wifi` symbol renders distinctly. Its bands are ~[0,0.33)=1 arc, [0.33,0.66)=2
# arcs, [0.66,1]=3 arcs, so values must land clearly inside a band. 0 = no arcs
# (the dimmed "searching" glyph).
const SIGNAL_VALUES = [0.0 0.2 0.5 1.0]
# The white Apple draws the `wifi` glyph's unfilled arcs in (30%), for dimming
# glyphs that have no variable value.
const DIM = "0x4dffffff"
# While joining (associated, waiting for an address) the icon animates: the
# arcs light up one by one, or the hotspot link brightens in three steps, from
# the dimmed glyph. `sketchybar-icons animate` swaps the frames and gives up
# after ANIMATION_SECONDS, so a join that never finishes can't keep the Mac
# awake; ANIMATION records its PID and which state it animates.
const ANIMATION = $"($CACHE_DIR)/wifi-animation.nuon"
const ANIMATION_SECONDS = 20
# sketchybar runs plugin scripts concurrently, and joining a network fires a
# burst of events; one run at a time decides the icon and the animation, or two
# runs both start an animator.
# System tools are called by full path: the launchd agent's PATH has only the
# nix packages sketchybar needs, not /bin.
const LOCK = $"($CACHE_DIR)/wifi.lock"

# Parse `power=on associated=yes ip=yes internet=online level=3 ...` into a
# record.
def parse-wifi [line: string] {
  $line
  | str trim
  | split row " "
  | reduce --fold {} {|it, acc|
      let kv = $it | split row "="
      $acc | insert $kv.0 $kv.1
    }
}

# True when tethered to a Personal Hotspot, via Location-free signals (SSID
# would need Location permission): macOS marks Wi-Fi "expensive" when the
# network's beacon carries Apple's personal-hotspot element (iPhones, and
# Android hotspots running Tetherbug), and iPhone USB/Bluetooth
# tethering hands out gateway 172.20.10.1. en0's IsExpensive lingers in
# ipconfig after leaving the hotspot, so it only counts while CoreWLAN says
# Wi-Fi is associated. Full paths since the launchd agent's PATH doesn't include
# /sbin or /usr/sbin.
def is-hotspot [wifi: record] {
  let expensive = ($wifi.associated? == "yes") and (
    ^/usr/sbin/ipconfig getsummary en0 | complete | get stdout | default ""
    | str contains "IsExpensive : TRUE")
  $expensive or (^/sbin/route -n get default | complete | get stdout | default ""
    | str contains "gateway: 172.20.10.1")
}

# The appearance for a state: what to draw, a cache key, and for the joining
# states the animation frames (the first is the static glyph).
def state-spec [state: record] {
  let associated = ($state.associated? | default "no") == "yes"
  # A missing `ip` field means a sketchybar-icons that doesn't report it, so it
  # counts as present.
  let has_ip = ($state.ip? | default "yes") == "yes"
  # Problems on a joined network come first, so a dead hotspot doesn't show the
  # working-hotspot glyph.
  if $associated and not $has_ip and (is-hotspot $state) {
    # Connecting to a hotspot: its glyph at the dimmed arcs' 30% white,
    # brightening in three steps.
    let frames = [$DIM "0x88ffffff" "0xc4ffffff" "0xffffffff"] | enumerate | each {|f|
      {sym: "personalhotspot", value: null, key: $"hotspot-joining-($f.index)", color: $f.item}
    }
    $frames.0 | insert frames $frames
  } else if $associated and not $has_ip {
    # Still connecting: joined, but DHCP hasn't produced an address. Control
    # Center draws the plain wifi glyph with its arcs unfilled — variableValue
    # 0 dims them exactly that way — then lights them one by one.
    let frames = $SIGNAL_VALUES | enumerate | each {|f|
      {sym: "wifi", value: $f.item, key: $"joining-($f.index)"}
    }
    $frames.0 | insert frames $frames
  } else if $associated and $state.internet? == "captive" {
    # A captive portal is waiting for login: full arcs with a lock badge.
    {
      sym: "wifi"
      value: 1.0
      badge: "lock.fill"
      key: "captive"
    }
  } else if $associated and $state.internet? == "offline" {
    # Joined with an address, but connections don't get past the access point.
    {sym: "wifi.exclamationmark", value: null, key: "nointernet"}
  } else if (is-hotspot $state) {
    # Works even if Wi-Fi is off and it's USB/BT tethered.
    {sym: "personalhotspot", value: null, key: "hotspot"}
  } else if ($state.power? | default "on") != "on" {
    {sym: "wifi.slash", value: null, key: "off"}
  } else if not $associated {
    # Radio on but not joined yet: macOS is still trying. Same dimmed glyph as
    # joining, but static: this can last indefinitely.
    {sym: "wifi", value: 0.0, key: "pending"}
  } else {
    let v = $SIGNAL_VALUES | get ($state.level | into int)
    {
      sym: "wifi"
      value: $v
      key: $"on-($v)"
    }
  }
}

# Render (or reuse) the PNG for a spec; return its path. Filename is derived
# from the appearance so sketchybar reloads on change and skips re-rendering
# when unchanged.
def render [spec: record] {
  let out = $"($CACHE_DIR)/wifi-($spec.key)-($POINT_SIZE)-w($MIN_WIDTH).png"
  if not ($out | path exists) {
    let value = if $spec.value != null { [--value $spec.value] } else { [] }
    let badge = if $spec.badge? != null { [--badge $spec.badge] } else { [] }
    let color = $spec.color? | default "0xffffffff"
    sketchybar-icons symbol --symbol $spec.sym ...$value ...$badge --point-size $POINT_SIZE --scale 2 --min-width $MIN_WIDTH --color $color --out $out
  }
  $out
}

# Stop the running animation, if it's still ours: the PID is checked against
# the process's command line first, since it may have exited (after its time
# limit) and the PID been reused. Waits for it to exit so it can't set a frame
# after the caller draws the next state.
def stop-animation [] {
  if not ($ANIMATION | path exists) { return }
  let pid = open $ANIMATION | get pid
  rm -f $ANIMATION
  let command = ^/bin/ps -p $pid -o command= | complete | get stdout
  if not ($command | str contains "sketchybar-icons animate") { return }
  do -i { ^/bin/kill $pid }
  for _ in 1..20 {
    if (^/bin/kill -0 $pid | complete | get exit_code) != 0 { break }
    sleep 50ms
  }
}

# Run the animation for `spec` if it has frames, else none; true if one is
# running, so the caller leaves the image to it. Leaves a running animation for
# the same state alone (and one that already hit its time limit stopped), so
# repeated events don't restart it.
def sync-animation [spec: record] {
  let state = $spec.key | str replace --regex '-0$' ""
  let current = if ($ANIMATION | path exists) { open $ANIMATION } else { null }
  if $current != null and $current.state == $state {
    return ((^/bin/kill -0 $current.pid | complete | get exit_code) == 0)
  }
  stop-animation
  if ($spec.frames? | is-empty) { return false }
  let frames = $spec.frames | each {|f| render $f } | str join ","
  let pid = ^/bin/sh -c 'sketchybar-icons animate --item "$1" --frames "$2" --interval 0.4 --for "$3" >/dev/null 2>&1 & echo $!' sh $env.NAME $frames $ANIMATION_SECONDS | str trim | into int
  {pid: $pid, state: $state} | save -f $ANIMATION
  # An animator that failed to start (e.g. a sketchybar-icons without
  # `animate`) leaves the caller to draw the static glyph.
  sleep 100ms
  (^/bin/kill -0 $pid | complete | get exit_code) == 0
}

# Run `body` holding LOCK. A lock older than a few seconds was left by a run
# that died, so it's taken over rather than waited on forever.
def locked [body: closure] {
  for _ in 1..100 {
    if (^/bin/mkdir $LOCK | complete | get exit_code) == 0 { break }
    # The lock may vanish between the mkdir and this check.
    try { if ((date now) - (ls -D $LOCK | get 0.modified)) > 5sec { rm -rf $LOCK } }
    sleep 50ms
  }
  try { do $body } catch {|e| print -e $"wifi: ($e.msg)" }
  rm -rf $LOCK
}

# Draw the icon for `line`, the daemon's state line or a fresh read, starting or
# stopping the joining animation to match.
def update [line: string] {
  let state = parse-wifi $line
  let spec = state-spec $state
  if not (sync-animation $spec) {
    sketchybar --set $env.NAME $"icon.background.image=(render $spec)"
  }
}

def main [] {

  # Geometry (icon.width=26, the bg_only highlight background) is owned by the
  # `sb-icon-item wifi` primitive + its --extra in sketchybarrc.nu — here we set
  # only the icon image. MIN_WIDTH centres the glyph WITHIN that footprint; no
  # x-shift nudge is needed once the footprint tiles cleanly.
  match $env.SENDER {
    "forced" => {
      locked { update (sketchybar-icons wifi) }
      # The one-shot read can't see the daemon's path-based verdict, so ask the
      # daemon to re-send its line; it arrives as a wifi_change.
      sketchybar-icons wifi --refresh
    }
    "wifi_change" | "routine" => {
      locked {
        let line = $env.WIFI_STATE? | default { sketchybar-icons wifi }
        # Concurrent runs can take the lock out of order. If the joined/address
        # state has moved on since this event, a newer event draws it.
        let fresh = parse-wifi (sketchybar-icons wifi)
        let event = parse-wifi $line
        if $event.associated? == $fresh.associated? and $event.ip? == $fresh.ip? {
          update $line
        }
      }
    }
    _ => {
      print $"wifi: ignoring event ($env.SENDER)"
    }
  }
}
