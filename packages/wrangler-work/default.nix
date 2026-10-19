{
  writeShellApplication,
  wrangler,
}:
# wrangler with its own login, so the work Cloudflare account lives beside the
# personal one instead of replacing it. wrangler reads `~/.wrangler` before any
# XDG path and has no override for it, so give it its own HOME.
# `wrangler-work login` once, then any wrangler subcommand.
writeShellApplication {
  name = "wrangler-work";
  runtimeInputs = [ wrangler ];
  text = ''
    home="$HOME/.local/share/wrangler-work"
    mkdir -p "$home"
    HOME="$home" exec wrangler "$@"
  '';
}
