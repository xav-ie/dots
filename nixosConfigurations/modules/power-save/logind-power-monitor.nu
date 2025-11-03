# Check if any non-idle sessions exist
def check_should_powersave [] {
  let result = (busctl call --json=pretty org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager ListSessions "" e> /dev/null | from json)
  let sessions = ($result.data.0 | default [])

  let has_active_session = ($sessions | any {|s|
    let prop_result = (busctl get-property --json=pretty org.freedesktop.login1 $"/org/freedesktop/login1/session/($s.0)" org.freedesktop.login1.Session IdleHint e> /dev/null | from json)
    let idle_hint = ($prop_result.data | default true)
    not $idle_hint
  })

  # Check if SSH sessions are active
  let ssh_active = (is-sshed) == "true"

  # Enter powersave only if no active sessions AND no SSH
  not $has_active_session and not $ssh_active
}

# Monitor logind for session property changes and manage power save state
def main [] {
  busctl monitor org.freedesktop.login1 e> /dev/null | lines | where {|line| $line =~ "Member=PropertiesChanged" } | each {|line|
    if (check_should_powersave) {
      print "All sessions idle/removed and no SSH - scheduling power save"
      systemctl restart --no-block power-save-enter-delayed.service
    } else {
      print "Active session or SSH detected - exiting power save"
      systemctl start power-save-exit.service
    }
  }
  return
}
