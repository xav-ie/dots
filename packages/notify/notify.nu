# Send a notification on Mac or Linux. If no body is provided, it
# generates a random kaomoji for you ☆⌒(ゝ。∂)
# Under an SSH/herdr remote session the notification goes to the laptop I
# attached from, falling back to this box if that host is unreachable.
def main [title: string, body?: string] {
  let body = match $body {
    null => (generate-kaomoji -r ".value")
    _ => $body
  }
  let script = $'display notification "($body)" with title "($title)"'
  match (uname | get kernel-name) {
    "Darwin" => (osascript -e $script)
    "Linux" => {
      let host = (ssh-client-host)
      let sent = if ($host | is-empty) { false } else {
        # The script goes over stdin so the remote shell never re-parses it.
        $script | ^ssh -o BatchMode=yes -o ConnectTimeout=3 $host osascript | complete | get exit_code | $in == 0
      }
      if not $sent { notify-send $title $body }
    }
  }
}
