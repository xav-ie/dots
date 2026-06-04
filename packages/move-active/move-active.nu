const bar_height = 34

def floatingWindowOrActive [use_active = false] {
  # first, try and get active window if it is floating
  let active_window = hyprctl activewindow -j | from json
  if ($active_window.floating == true or $use_active) {
    $active_window
  } else {
    # now, try and find the first floating window on the current workspace
    let active_workspace = hyprctl activeworkspace -j | from json
    let floating_workspace_windows = (hyprctl clients -j
                                      | from json
                                      | where
                                        $it.workspace.id == $active_workspace.id
                                        and floating == true
                                      | sort-by focusHistoryID)
    let chosen_floating = $floating_workspace_windows | first
    $chosen_floating
  }
}

def getWindowBySelector [selector: string] {
  let clients = hyprctl clients -j | from json

  # Parse different selector types
  if ($selector | str starts-with "title:") {
    let title_pattern = ($selector | str replace "title:" "")
    $clients | where title =~ $title_pattern | first
  } else if ($selector | str starts-with "class:") {
    let class_pattern = ($selector | str replace "class:" "")
    $clients | where class =~ $class_pattern | first
  } else if ($selector | str starts-with "address:") {
    let address = ($selector | str replace "address:" "")
    $clients | where address == $address | first
  } else {
    # Default to class if no prefix
    $clients | where class =~ $selector | first
  }
}

def windowDimensions [use_active = false, selector = ""] {
  let window = if ($selector | is-not-empty) {
    try { getWindowBySelector $selector } catch {
      print -e "Could not find window to act on"
      exit 0
    }
  } else {
    floatingWindowOrActive $use_active
  }

  {
    width: $window.size.0
    height: $window.size.1
    x: $window.at.0
    y: $window.at.1
    address: $window.address
  }
}

def windowInfo [
  window_dimensions:
    record<width: number, height: number, x: number, y: number, address: string>,
] {
  let border_size = (hyprctl getoption general:border_size -j
                     | from json | get int)
  let gaps = (hyprctl getoption general:gaps_out -j
              | from json | get custom | split words
              | each {|| $in | into int })
  let gap_top = $gaps.0
  let gap_right = $gaps.1
  let gap_bottom = $gaps.2
  let gap_left = $gaps.3

  let screen_dimensions = (hyprctl monitors -j
                           | from json
                           | where focused == true
                           | first
                           | select width height x y)
  let screen_height = $screen_dimensions.height
  let screen_width = $screen_dimensions.width

  let window_height = $window_dimensions.height
  let window_width = $window_dimensions.width

  let window_left = $gap_left + $border_size
  let window_top = $gap_top + $border_size + $bar_height + $border_size + $gap_top
  let window_right = $screen_width - $window_width - $gap_right - $border_size
  let window_bottom = $screen_height - $window_height - $gap_bottom - $border_size
  let window_h_middle = ($screen_width - $window_width) / 2
  let window_v_middle = ($window_top
                        + ($window_bottom - $window_top) / 2)

  # Pick the anchor (left/middle/right, top/middle/bottom) the window is
  # currently closest to so resize can preserve it.
  let window_quadrant = {
    v: ([
        { name: "top", pos: $window_top },
        { name: "middle", pos: $window_v_middle },
        { name: "bottom", pos: $window_bottom },
      ]
      | each {|c| { name: $c.name, dist: ($c.pos - $window_dimensions.y | math abs) } }
      | sort-by dist
      | first
      | get name),
    h: ([
        { name: "left", pos: $window_left },
        { name: "middle", pos: $window_h_middle },
        { name: "right", pos: $window_right },
      ]
      | each {|c| { name: $c.name, dist: ($c.pos - $window_dimensions.x | math abs) } }
      | sort-by dist
      | first
      | get name),
  }

  {
    window_left: $window_left,
    window_right: $window_right,
    window_bottom: $window_bottom,
    window_top: $window_top,
    window_h_middle: $window_h_middle,
    window_v_middle: $window_v_middle,
    window_dimensions: $window_dimensions,
    window_quadrant: $window_quadrant,
    address: $window_dimensions.address,
  }
}

def reset_position [] {
  hyprctl dispatch moveactive exact 0 0
}

def move_position [
  position: record<v: string, h: string>,
  use_active = false,
  selector = "",
  window_dimensions_override?:
    record<width: number, height: number, x: number, y: number, address: string>,
] {
  let window_info = windowInfo ($window_dimensions_override | default
                                (windowDimensions $use_active $selector))
  let y = match $position.v {
    "top" => $window_info.window_top
    "middle" => $window_info.window_v_middle
    "bottom" => $window_info.window_bottom
  } | math round
  let x = match $position.h {
    "left" => $window_info.window_left
    "middle" => $window_info.window_h_middle
    "right" => $window_info.window_right
  } | math round
  let resize_params = $"exact ($x) ($y)"

  let command = if $use_active {
    $"moveactive ($resize_params)"
  } else if ($selector != "") {
    $"movewindowpixel ($resize_params),($selector)"
  } else {
    $"movewindowpixel ($resize_params),address:($window_info.address)"
  }
  $command
}

def move_window [position: record<v: string, h: string>, selector = ""] {
  hyprctl dispatch (move_position $position false $selector)
}

# Move window to top left
export def "main topLeft" [selector = ""] {
  move_window { v: "top", h: "left" } $selector
}

# Move window to top right
export def "main topRight" [selector = ""] {
  move_window { v: "top", h: "right" } $selector
}

# Move window to bottom right
export def "main bottomRight" [selector = ""] {
  move_window { v: "bottom", h: "right" } $selector
}

# Move window to bottom left
export def "main bottomLeft" [selector = ""] {
  move_window { v: "bottom", h: "left" } $selector
}

# Move window to top middle
export def "main topMiddle" [selector = ""] {
  move_window { v: "top", h: "middle" } $selector
}

# Move window to middle middle (center)
export def "main middleMiddle" [selector = ""] {
  move_window { v: "middle", h: "middle" } $selector
}

# Move window to bottom middle
export def "main bottomMiddle" [selector = ""] {
  move_window { v: "bottom", h: "middle" } $selector
}

# If the active window cannot be grown or shrunk, then don't use it!
# Use the most recent floating window instead.
def should_use_active [] {
  (hyprctl clients -j | from json
  | where { ||
     $in.workspace.id == 1 and not $in.floating
   }
  | length) > 1
}

# Smartly resize a window respecting its current corner.
def resize [percentage: number] {
  let window_info = windowInfo (windowDimensions (should_use_active) "")

  let resized_width = ($window_info.window_dimensions.width
                       * (1 + $percentage) | math round)
  let resized_height = ($window_info.window_dimensions.height
                        * (1 + $percentage) | math round)
  # pre-calculate the resized, desired window dimensions for moving
  let window_dimensions_override = {
    width: $resized_width,
    height: $resized_height,
    x: $window_info.window_dimensions.x,
    y: $window_info.window_dimensions.y,
    address: $window_info.address,
  }

  let move_command = (move_position $window_info.window_quadrant (should_use_active) ""
                      $window_dimensions_override)
  let batchCommand = [
    $"dispatch resizewindowpixel exact ($resized_width) ($resized_height),address:($window_info.address)"
    $"dispatch ($move_command)"
  ]
  print $"batchCommand ($batchCommand); \ndispactch ($move_command)"
  (hyprctl --batch ($batchCommand | str join ";\n"))
}

# Shrink active window by 10%
export def "main shrink" [] {
  resize -0.1
}

# Grow active window by 10%
export def "main grow" [] {
  resize 0.1
}

# Get floating window info
export def main [] {
  floatingWindowOrActive true
}
