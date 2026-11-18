# Send a notification on Mac or Linux. If no body is provided, it
# generates a random kaomoji for you ☆⌒(ゝ。∂)
#
# It shows on the screen I'm at. On Linux that is this box while I'm at its
# seat (at-computer); otherwise the laptop driving it over SSH/herdr --remote,
# falling back to this box if that host is unreachable.
#
# NOTIFY_ICONS, NOTIFIER and AT_COMPUTER are consts prepended by default.nix.

def short-hostname []: nothing -> string {
  sys host | get hostname | split row "." | first
}

# Avatar for an icon name. A notification shown away from where it was sent
# uses the sender's variant (claude-praesidium) when one exists.
def icon-path [icon, origin: string]: nothing -> any {
  if $icon == null { return null }
  let variant = $NOTIFY_ICONS | path join $"($icon)-($origin).png"
  let plain = $NOTIFY_ICONS | path join $"($icon).png"
  if $origin != (short-hostname) and ($variant | path exists) {
    $variant
  } else if ($plain | path exists) {
    $plain
  } else { null }
}

# What clicking the notification runs, as argv.
def on-click [p: record]: nothing -> any {
  if ($p.herdrTab? | is-empty) { return null }
  ["notify" "focus" $p.origin $p.herdrTab]
}

# Show the payload on this machine.
def show [p: record] {
  let icon = icon-path ($p.icon? | default null) $p.origin
  let click = on-click $p
  match (uname | get kernel-name) {
    "Darwin" => {
      {
        title: $p.title
        body: $p.body
        icon: $icon
        group: ($p.icon? | default null)
        expireAt: ($p.expireAt? | default null)
        onClick: $click
      }
      | to json
      | ^$NOTIFIER post
    }
    "Linux" => {
      # Hints read by the notification center (packages/notification-center).
      let hints = (
        [
          (if $icon != null { $"string:image-path:($icon)" })
          (if ($p.expireAt? | is-not-empty) { $"string:x-dots-expire-at:($p.expireAt)" })
          (if $click != null { $"string:x-dots-on-click:($click | to json -r)" })
        ]
        | compact
        | each {|h| ["-h" $h] }
        | flatten
      )
      ^notify-send ...$hints $p.title $p.body
    }
  }
}

# Linux: the screen I'm at. Darwin: always here.
def deliver [p: record] {
  if (uname | get kernel-name) == "Linux" and $AT_COMPUTER != null {
    let here = (^$AT_COMPUTER | complete | get exit_code) == 0
    if not $here {
      let host = (ssh-client-host)
      let sent = if ($host | is-empty) { false } else {
        # The payload goes over stdin so the remote shell never re-parses it.
        $p | to json | ^ssh -o BatchMode=yes -o ConnectTimeout=3 $host notify show | complete | get exit_code | $in == 0
      }
      if $sent { return }
    }
  }
  show $p
}

def main [
  title: string
  body?: string
  --icon: string # avatar from notify-icons: claude, morning, evening
  --expire: duration # remove it from the notification list after this long
  --herdr-tab: string # clicking focuses this herdr tab and its terminal
] {
  let body = match $body {
    null => (generate-kaomoji -r ".value")
    _ => $body
  }
  let expire_at = if $expire == null { null } else {
    (date now) + $expire | into int | $in // 1_000_000_000
  }
  deliver {
    title: $title
    body: $body
    icon: $icon
    origin: (short-hostname)
    expireAt: $expire_at
    herdrTab: $herdr_tab
  }
}

# Show a payload forwarded from another machine's `notify` (JSON on stdin).
def "main show" [] {
  show ($in | from json)
}

# Focus the terminal attached to <origin>'s herdr, then the tab itself.
def "main focus" [origin: string, tab: string] {
  # Ghostty titles herdr windows "<host>: <workspace>".
  let prefix = $"($origin): "
  match (uname | get kernel-name) {
    "Darwin" => {
      let win = (
        ^yabai -m query --windows
        | from json
        | where app == "Ghostty" and ($it.title | str starts-with $prefix)
        | get -o 0.id
      )
      if $win != null { ^yabai -m window --focus $win } else { ^open -a Ghostty }
    }
    "Linux" => {
      let win = (
        ^hyprctl clients -j
        | from json
        | where ($it.class | str contains "ghostty") and ($it.title | str starts-with $prefix)
        | get -o 0.address
      )
      if $win != null { ^hyprctl dispatch ('hl.dsp.focus({ window = "address:' + $win + '" })') }
    }
  }
  if $origin == (short-hostname) {
    ^herdr tab focus $tab
  } else {
    ^ssh -o BatchMode=yes -o ConnectTimeout=3 $origin herdr tab focus $tab
  }
}
