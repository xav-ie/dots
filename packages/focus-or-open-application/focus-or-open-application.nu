def main [appName: string] {
  try {
    let winds = (yabai -m query --windows
                | from json
                | where app   == $appName and
                        title != "Picture-in-Picture")

    if ($winds | is-empty) {
      error make { msg: "no winds" }
    }

    let focused_num = ($winds | where "has-focus" == true | length)

    let target = if ($focused_num == 1) {
      # Same app: cycle to least recently focused
      $winds | last
    } else {
      # Different app: most recently focused (first in list)
      $winds | first
    }
    yabai -m window --focus $target.id
  } catch {
    try {
      ^open (mdfind kMDItemContentTypeTree=com.apple.application-bundle
            | grep $'/($appName).app$')
    } catch {
      notify $"Could not focus or open '($appName)'"
    }
  }
}
