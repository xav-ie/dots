def main [prompt?: string] {
  let title = match $prompt {
    null | "" => "Authentication Required",
    _ => $prompt
  }
  ^zenity --password --title=$"($title)" err> /dev/null
}
