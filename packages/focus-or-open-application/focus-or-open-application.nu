def main [...appNames: string] {
  if ($appNames | is-empty) {
    error make { msg: "at least one app name required" }
  }

  let allWinds = try {
    yabai -m query --windows
    | from json
    | where title != "Picture-in-Picture"
  } catch {
    []
  }

  let appsWithWindows = ($appNames | each {|app|
    {
      app: $app,
      windows: ($allWinds | where app == $app)
    }
  })

  # Launch any apps that have no visible windows. If we had to launch
  # anything, stop here — the OS handles initial focus, and a follow-up
  # press will cycle once yabai picks up the new windows.
  let missing = ($appsWithWindows | where {|row| $row.windows | is-empty } | get app)
  if not ($missing | is-empty) {
    for app in $missing {
      try {
        ^open (mdfind kMDItemContentTypeTree=com.apple.application-bundle
              | grep $'/($app).app$')
      } catch {
        osascript -e $'display notification "Could not open \'($app)\'" with title "focus-or-open-application"'
      }
    }
    return
  }

  let target = if (($appNames | length) == 1) {
    # Single app: cycle through that app's windows
    let winds = ($appsWithWindows | first | get windows)
    let focused_num = ($winds | where has-focus == true | length)
    if ($focused_num == 1) {
      $winds | last
    } else {
      $winds | first
    }
  } else {
    # Multi-app: cycle focus through the list
    let focused_matches = ($appsWithWindows
      | enumerate
      | where {|row| $row.item.windows | any {|w| $w.has-focus == true } })

    let target_idx = if ($focused_matches | is-empty) {
      0
    } else {
      (($focused_matches | first | get index) + 1) mod ($appNames | length)
    }

    $appsWithWindows | get $target_idx | get windows | first
  }

  yabai -m window --focus $target.id
}
