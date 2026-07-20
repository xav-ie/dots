# Is someone actively driving this box from elsewhere? True for a plain SSH
# login (a `pts`) OR a herdr remote session. herdr attaches over SSH but the
# panes run under the long-lived `herdr server`, not the SSH session, so `who`
# shows no `pts` — instead we look for the per-connection `remote-client-bridge`
# process herdr spawns while a remote client is attached.
def main [] {
  if (who -u | str contains "pts") { return true }
  ls /proc/*/cmdline
  | get name
  | any {|f| (try { open --raw $f | decode utf-8 } catch { "" }) =~ "remote-client-bridge" }
}
