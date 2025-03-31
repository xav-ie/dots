{
  writeShellApplication,
  libnotify,
  generate-kaomoji,
}:
writeShellApplication {
  name = "notify";
  runtimeInputs = [ libnotify ];
  text = ''
    title="''${1}"
    body="''${*:2}"
    if [[ -z "$body" ]]; then
      body="$(${generate-kaomoji} -- -r ".value")"
    fi

    if [[ -n "$(command -v osascript)" ]]; then
      osascript -e "display notification \"$body\" with title \"$title\""
    else
      notify-send "$title" "$body"
    fi
  '';
}
