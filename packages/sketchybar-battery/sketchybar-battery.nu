def main [] {
  # immediately update on results received
  $env.config.table.stream_page_size = 1

  # pmset -g pslog streams a block on every power-source/charge change. The
  # InternalBattery line carries both the percentage and the charge state, e.g.
  #   -InternalBattery-0 (id=8519779)	88%; discharging; 8:20 remaining present: true
  # We parse both so the native battery icon can pick the right glyph/color and
  # show the charging bolt without any screen-recording alias.
  (pmset -g pslog
  | lines
  | where {|| $in =~ "InternalBattery" }
  | parse -r '(?<percent>\d?\d?\d)%; (?<state>[\w ]+?);'
  | where percent != ""
  | each {|row|
      let charging = ($row.state == "charging")
      # Anything that isn't actively discharging is on external power (charging,
      # charged, or "AC attached; not charging").
      let ac = ($row.state != "discharging")
      sketchybar --trigger battery_change BATTERY=($row.percent) CHARGING=($charging) AC=($ac)
    }
  | ignore)
}
