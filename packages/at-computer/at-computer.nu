# Is someone sitting at this computer right now? True when the user has a
# desktop (Wayland) session and hypridle hasn't marked the seat away, which it
# does after a minute without keyboard or mouse input (modules/home-linux/
# hyprland/hyprland.nix). So sudo over ssh, herdr --remote or collie reads as
# away even though a desktop session exists.
#
# Unlike is-sshed ("is a remote session attached?"), this answers where a prompt
# should appear: on this screen, or in the terminal that asked.
#
# Only nushell builtins, no external commands: pam_exec runs it with no PATH.
def main [
  user?: string # whose seat; defaults to the caller (root passes it, e.g. from PAM)
] {
  let name = $user | default (whoami)
  let uid = open /etc/passwd
  | lines
  | split column ':' name password uid
  | where name == $name
  | get -o 0.uid
  let runtime = $"/run/user/($uid)"
  let session = try {
    ls $runtime
    | where type == socket and ($it.name | path basename) =~ '^wayland-\d+$'
    | is-not-empty
  } catch { false }
  let here = $uid != null and $session and not ($runtime | path join seat-away | path exists)
  print $here
  if not $here { exit 1 }
}
