# The volume_change event supplies a $INFO variable in which the current volume
# percentage is passed to the script.
def main [] {
  if $env.SENDER == "volume_change" {
    let volume = ($env.INFO | into int)
    let settings = match $volume {
      # muted
      0 => ["􀊣" 14.0 6]
      # no bars
      1..24 => ["􀊡" 14.0 10]
      # one bar
      25..49 => ["􀊥" 14.0 6]
      # two bars
      50..74 => ["􀊧" 14.0 3]
      # three bars
      75..100 => ["􀊩" 14.0 0]
    }
    sketchybar --set $"($env.NAME)" $"icon=($settings.0)" $"icon.font.size=($settings.1)" $"icon.padding_right=($settings.2)" $"label=($volume)%"
  }
}
