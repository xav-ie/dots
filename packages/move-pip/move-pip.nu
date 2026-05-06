def get-pip-info []: nothing -> record<w: float, h: float, x: float, y: float, id: int, display: int> {
  try {
    yabai -m query --windows
    | jq -r '[.[] | select(.title=="Picture-in-Picture" or .app=="iPhone Mirroring")][0]'
    | from json
    | {
        w: $in.frame.w,
        h: $in.frame.h,
        x: $in.frame.x,
        y: $in.frame.y,
        id: $in.id,
        display: $in.display
      }
  } catch {
    error make --unspanned {
      msg: "Could not find any PiP or iPhone Mirroring windows."
    }
  }
}

def get-screen-id-dimensions [screenId: int]: nothing -> record<screenWidth: float, screenHeight: float> {
  yabai -m query --displays
  | jq --argjson id $"($screenId)" '.[] | select(.id==$id) | {screenWidth: .frame.w, screenHeight: .frame.h}'
  | from json
}

# returns both the pip and containing screen dimensions
def get-pip-info-full []: nothing -> record<w: float, h: float, x: float, y: float, id: int, display: int, screenWidth: float, screenHeight: float> {
  let pipInfo = (get-pip-info)
  let screenDimensions = get-screen-id-dimensions ($pipInfo.display)
  {
    ...$pipInfo,
    ...$screenDimensions
  }
}

export def main [] {
  help main
}

# move window to top left
export def "main top-left" []: nothing -> nothing {
  let pipInfo = (get-pip-info-full)
  yabai -m window $"($pipInfo.id)" --move abs:0:0
}

# move window to top right
export def "main top-right" []: nothing -> nothing {
  let pipInfo = (get-pip-info-full)
  let moveX = $pipInfo.screenWidth - $pipInfo.w
  yabai -m window $"($pipInfo.id)" --move $"abs:($moveX):0"
}

# move window to bottom right
export def "main bottom-right" []: nothing -> nothing {
  let pipInfo = (get-pip-info-full)
  let moveX = $pipInfo.screenWidth - $pipInfo.w
  let moveY = $pipInfo.screenHeight - $pipInfo.h
  yabai -m window $"($pipInfo.id)" --move $"abs:($moveX):($moveY)"
}

# move window to bottom left
export def "main bottom-left" []: nothing -> nothing {
  let pipInfo = (get-pip-info-full)
  let moveY = $pipInfo.screenHeight - $pipInfo.h
  yabai -m window $"($pipInfo.id)" --move $"abs:0:($moveY)"
}

export def "main top-middle" []: nothing -> nothing {
  let pipInfo = (get-pip-info-full)
  let moveX = ($pipInfo.screenWidth - $pipInfo.w) / 2
  yabai -m window $"($pipInfo.id)" --move $"abs:($moveX):0"
}

export def "main middle-middle" []: nothing -> nothing {
  let pipInfo = (get-pip-info-full)
  let moveX = ($pipInfo.screenWidth - $pipInfo.w) / 2
  let moveY = ($pipInfo.screenHeight - $pipInfo.h) / 2
  yabai -m window $"($pipInfo.id)" --move $"abs:($moveX):($moveY)"
}

export def "main bottom-middle" []: nothing -> nothing {
  let pipInfo = (get-pip-info-full)
  let moveX = ($pipInfo.screenWidth - $pipInfo.w) / 2
  let moveY = $pipInfo.screenHeight - $pipInfo.h
  yabai -m window $"($pipInfo.id)" --move $"abs:($moveX):($moveY)"
}

def smart-resize [factor: float]: nothing -> nothing {
  let info = (get-pip-info-full)
  let centerX = $info.x + $info.w / 2
  let centerY = $info.y + $info.h / 2
  let newW = ($info.w * (1 + $factor) | math round)
  let newH = ($info.h * (1 + $factor) | math round)
  let anchorX = if $centerX < ($info.screenWidth / 3) {
    "left"
  } else if $centerX > ($info.screenWidth * 2 / 3) {
    "right"
  } else {
    "middle"
  }
  let anchorY = if $centerY < ($info.screenHeight / 3) {
    "top"
  } else if $centerY > ($info.screenHeight * 2 / 3) {
    "bottom"
  } else {
    "middle"
  }
  let newX = if $anchorX == "left" {
    $info.x | math round
  } else if $anchorX == "right" {
    ($info.x + $info.w - $newW) | math round
  } else {
    ($info.x + ($info.w - $newW) / 2) | math round
  }
  let newY = if $anchorY == "top" {
    $info.y | math round
  } else if $anchorY == "bottom" {
    ($info.y + $info.h - $newH) | math round
  } else {
    ($info.y + ($info.h - $newH) / 2) | math round
  }
  yabai -m window $"($info.id)" --resize $"abs:($newW):($newH)"
  yabai -m window $"($info.id)" --move $"abs:($newX):($newY)"
}

# Shrink the PiP window by 10%, keeping its current corner anchored.
export def "main shrink" []: nothing -> nothing {
  smart-resize -0.1
}

# Grow the PiP window by 10%, keeping its current corner anchored.
export def "main grow" []: nothing -> nothing {
  smart-resize 0.1
}
