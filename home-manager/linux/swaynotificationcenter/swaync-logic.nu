#!/usr/bin/env nu

def main [action: string] {
    let count_file = $"($env.XDG_RUNTIME_DIR)/swaync-visible-count"
    let notification_height = ($env.NOTIFICATION_HEIGHT | into int)
    let notification_width = ($env.NOTIFICATION_WIDTH | into int)
    let max_height = ($env.MAX_HEIGHT | into int)

    # Update counter
    let current = if ($count_file | path exists) { open $count_file | into int } else { 0 }
    let new_count = match $action {
        "increment" => ($current + 1),
        "decrement" => ([($current - 1), 0] | math max),
        _ => $current
    }
    $new_count | into string | save -f $count_file

    # Resize window
    let calculated = $new_count * $notification_height
    let height = [$calculated $notification_height] | math max | [$in $max_height] | math min
    hyprctl dispatch resizewindowpixel $"exact ($notification_width) ($height),class:^swaync$"
}
