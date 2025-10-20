# Rofi-based power menu written in Nushell
def main [] {
  # Power menu options
  let options = [
    { icon: "󰍁", action: "lock" }
    { icon: "󰤄", action: "suspend" }
    { icon: "󰍃", action: "logout" }
    { icon: "󰜉", action: "reboot" }
    { icon: "󰐥", action: "shutdown" }
  ]

  # Get uptime
  let uptime = (uptime | split row "," | get 0 | split row "up" | get 1 | str trim)

  # Display menu and get selection
  let chosen = (
    $options
    | get icon
    | str join "\n"
    | rofi -dmenu -p $"Goodbye ($env.USER)" -mesg $"Uptime: ($uptime)" -theme $env.ROFI_POWERMENU_THEME
  )

  # Find which action was selected
  let action = (
    $options
    | where icon == $chosen
    | get -o 0.action
  )

  # If nothing selected, exit
  if ($action | is-empty) {
    return
  }

  # Confirmation dialog
  let confirm_options = ["✓", "✗"]

  let confirmed = (
    $confirm_options
    | str join "\n"
    | rofi -dmenu -p "Confirmation" -mesg "Are you Sure?" -theme $env.ROFI_POWERMENU_THEME
  )

  # Check if confirmed (yes = ✓)
  if $confirmed != "✓" {
    return
  }

  # Execute the action
  match $action {
    "lock" => { hyprlock }
    "suspend" => { systemctl suspend }
    "logout" => { hyprctl dispatch exit }
    "reboot" => { systemctl reboot }
    "shutdown" => { systemctl poweroff }
    _ => { }
  }
}
