def main [] {
  let percentage = (pmset -g batt | grep -Eo "\\d+%" | cut -d% -f1)
  if $percentage == "" {
    return;
  }

  sketchybar --set $"($env.NAME)" "icon.padding_left=0" "icon.padding_right=4" $"label=($percentage)%"
}
