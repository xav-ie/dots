def main [] {
  if $env.SENDER == "front_app_switched" {
    sketchybar --set $"($env.NAME)" $"label=($env.INFO)" $"icon.background.image=app.($env.INFO)" "icon.background.image.scale=0.95"
  }
}
