#!/usr/bin/env nu --stdin

# gets all control center item names
export def get_items [] {
  let items = (osascript -e 'set text item delimiters to linefeed'
              -e 'tell application "System Events" to tell process "ControlCenter" to (get description of every menu bar item of menu bar 1) as text'
              | lines
              | each {|| $in
                        | parse -r "^(?<name>[^,]+)"
                        | first
                        | get name
                        | str trim
                        | str replace -a "‑" "-"
              })
  $items
}

# gets the index of the control center item with the given name
export def find_item [item: string] {
  let items = (get_items)

  let result = $items
  | enumerate
  | where {|row| $row.item == $item}
  | first
  | get index

  $result + 1
}

# click the item in control center with the given name
export def select_item [item: string] {
  let index = (find_item $item)
  osascript -e $"tell application \"System Events\" to tell process \"Control Center\" to perform action \"AXPress\" of menu bar item ($index) of menu bar 1" | ignore
}

# select the item in control center with the given name
def main [item: string] {
  select_item $item
}
