def main --wrapped [...args] {
  let parts = $args | split list "--"
  ^nom build --no-link ...$parts.0
  ^nix run ...$args
}
