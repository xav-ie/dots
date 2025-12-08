def main [] {
  # immediately update on results received
  $env.config.table.stream_page_size = 1

  (pmset -g pslog
  | lines
  | where {||$in =~ "%"}
  | parse -r '(?<percent>\d?\d?\d)%'
  | get percent
  | each {|| sketchybar --trigger battery_change BATTERY=($in) }
  | ignore)
}
