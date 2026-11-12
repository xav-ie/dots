#!/usr/bin/env nu --stdin

# macOS 27 hosts the system status items in MenuBarAgent, each wrapped in an
# AXGroup and identified only by AXIdentifier com.apple.menuextra.<id>.
const IDS = {
  "Control Center": "controlcenter"
}

const PRESS = '
on run argv
  tell application "System Events" to tell process "MenuBarAgent"
    repeat with g in (every group of menu bar 1)
      set i to menu bar item 1 of g
      if value of attribute "AXIdentifier" of i is (item 1 of argv) then
        perform action "AXPress" of i
        return
      end if
    end repeat
  end tell
  error "no menu bar item " & (item 1 of argv)
end run'

# click the status item with the given name
export def select_item [item: string] {
  let id = $"com.apple.menuextra.($IDS | get $item)"
  menubar-reveal osascript -e $PRESS $id | ignore
}

def main [item: string] {
  select_item $item
}
