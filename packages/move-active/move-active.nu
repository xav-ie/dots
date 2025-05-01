const waybar_height = 34

export def windowDimensions [] {
  hyprctl activewindow -j
  | jq '{
    width: .size[0],
    height: .size[1],
    x: .at[0],
    y: .at[1],
  }'
  | from json
}

export def windowInfo [
  window_dimensions_override?:
    record<width: number, height: number, x: number, y: number>
] {
  let border_size = (hyprctl getoption general:border_size -j
                     | jq .int) | from json
  let gaps = (hyprctl getoption general:gaps_out -j
              | jq '.custom | split (" ") | map(tonumber)')
              | from json
  let gap_top = $gaps.0
  let gap_right = $gaps.1
  let gap_bottom = $gaps.2
  let gap_left = $gaps.3

  let screen_dimensions = (hyprctl monitors -j
                           | jq 'map(select(.focused == true))
                                  | .[]
                                  | {
                                      width: .width,
                                      height: .height,
                                      x: .x,
                                      y: .y,
                                    }')
                           | from json
  let screen_height = $screen_dimensions.height
  let screen_width = $screen_dimensions.width
  let screen_center = {
    x: ($screen_dimensions.x + $screen_dimensions.width / 2),
    y: ($screen_dimensions.y + $screen_dimensions.height / 2),
  }

  let window_dimensions = $window_dimensions_override | default (windowDimensions)
  let window_height = $window_dimensions.height
  let window_width = $window_dimensions.width
  let window_center = {
    x: ($window_dimensions.x + $window_dimensions.width / 2),
    y: ($window_dimensions.y + $window_dimensions.height / 2),
  }
  let window_quadrant = {
    top: ($window_center.y < $screen_center.y),
    left: ($window_center.x < $screen_center.x),
  }

  let window_left = $gap_left + $border_size
  let window_top = $gap_top + $border_size + $waybar_height + $border_size + $gap_top
  let window_right = $screen_width - $window_width - $gap_right - $border_size
  let window_bottom = $screen_height - $window_height - $gap_bottom - $border_size

  {
    window_left: $window_left,
    window_right: $window_right,
    window_bottom: $window_bottom,
    window_top: $window_top,
    window_dimensions: $window_dimensions,
    window_quadrant: $window_quadrant,
  }
}

export def reset [] {
  hyprctl dispatch moveactive exact 0 0
}

export def move_position [
  position: record<top: bool, left: bool>,
  window_dimensions_override?:
    record<width: number, height: number, x: number, y: number>
] {
  let window_info = windowInfo ($window_dimensions_override
                                | default (windowDimensions))
  # rounding bad?
  let top = $window_info.window_top | math round
  let bottom = $window_info.window_bottom | math round
  let left = $window_info.window_left | math round
  let right = $window_info.window_right | math round

  match $position {
    { top: true, left: true } =>
      { $"moveactive exact ($left) ($top)" }
    { top: true, left: false } =>
      { $"moveactive exact ($right) ($top)" }
    { top: false, left: false } =>
      { $"moveactive exact ($right) ($bottom)" }
    { top: false, left: true } =>
      { $"moveactive exact ($left) ($bottom)" }
  }
}

export def move_position_test [] {
  move_position {top: true, left: true}
}

export def move [position: record<top: bool, left: bool>] {
  hyprctl dispatch (move_position $position)
}

export def topLeft [] {
  move { top: true, left: true }
}

export def topRight [] {
  move { top: true, left: false }
}

export def bottomRight [] {
  move { top: false, left: false }
}

export def bottomLeft [] {
  move { top: false, left: true }
}

# Smartly resize a window respecting its current corner.
export def resize [percentage: number] {
  let window_info = windowInfo (windowDimensions)
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
  }

  # Does not work properly, maybe in the next release. Or, pre-calculate the moved coordinates.
  hyprctl --batch $"dispatch resizeactive exact ($resized_width) ($resized_height) ;
                    dispatch (move_position
                              $window_info.window_quadrant $window_dimensions_override)"
}

export def shrink [] {
  resize -0.1
}

export def grow [] {
  resize 0.1
}
