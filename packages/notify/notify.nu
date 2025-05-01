# Send a notification on Mac or Linux. If no body is provided, it
# generates a random kaomoji for you ☆⌒(ゝ。∂)
def main [title: string, body?: string] {
  let body = match $body {
    null => (generate-kaomoji -r ".value")
    _ => $body
  }
  match (uname | get kernel-name) {
    "Darwin" => (osascript -e $'display notification "($body)" with title "($title)"')
    "Linux" => (notify-send $"($title)" $"($body)")
  }
}
