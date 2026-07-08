def yabai-up []: nothing -> bool {
  (try { yabai -m query --displays e> /dev/null | from json | length } | default 0) > 0
}

let uid = (^id -u | str trim)

print "Restarting yabai..."
launchctl kickstart -k $"gui/($uid)/org.nixos.yabai"

# Wait for the new instance to create its socket and accept queries.
# Transient "failed to connect to socket" errors during this window are
# expected, so stderr is discarded in yabai-up.
mut ready = false
for _ in 0..40 {
  if (yabai-up) {
    $ready = true
    break
  }
  sleep 250ms
}

if not $ready {
  error make --unspanned {
    msg: "yabai did not come back up after kickstart. Try a full logout/login or reboot."
  }
}
print "yabai is back up."

# Re-load the scripting addition. The NOPASSWD sudoers rule pins the exact
# yabai store path, so resolve the symlink and use `sudo -n` (no prompt /
# no hang) — a bare `yabai` would miss the rule and ask for a password.
let yabai_bin = (which yabai | get path.0 | path expand)
let sa = (sudo -n $yabai_bin --load-sa | complete)
if $sa.exit_code == 0 {
  print "Reloaded scripting addition."
} else {
  # Non-zero is normal: yabai already loads the SA on startup, so this
  # call just reports it's already injected. (A literal "(" in an
  # interpolated string must be escaped, else nu parses it as a command.)
  print $"Scripting addition already loaded; load-sa exit ($sa.exit_code)."
}

# Reset every window's sub-layer to normal (fixes windows stuck above/below).
let count = (
  yabai -m query --windows
  | from json
  | get id
  | each { |id| try { yabai -m window $id --sub-layer normal } }
  | length
)
print $"Reset sub-layer on ($count) windows. Done."
