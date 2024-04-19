{ writeShellApplication, libnotify }:
# I think it would be better to make this a flake
writeShellApplication {
  name = "notify";
  runtimeInputs = [ libnotify ];
  # HOW DO YOU USE FLAKES????
  # I would prefer to have generate-kaomoji as a fixed input
  text = ''
    title="''${1}"
    body="''${*:2}"
    if [[ -z "$body" ]]; then
      body="$(nix run github:xav-ie/generate-kaomoji -- -r ".value")"
    fi

    if [[ -n "$(command -v osascript)" ]]; then
      osascript -e "display notification \"$body\" with title \"$title\""
    else
      notify-send "$title" "$body"
    fi
  '';
}
