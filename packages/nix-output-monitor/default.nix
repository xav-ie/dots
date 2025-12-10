{ nix-output-monitor }:

# Custom nix-output-monitor with Nerd Font icons
# https://haseebmajid.dev/posts/2025-08-10-til-how-to-change-emojis-in-nh/
nix-output-monitor.overrideAttrs (old: {
  postPatch = old.postPatch or "" + ''
    substituteInPlace lib/NOM/Print.hs \
      --replace 'down = "↓"' 'down = "\xf072e"' \
      --replace 'up = "↑"' 'up = "\xf0737"' \
      --replace 'clock = "⏱"' 'clock = "\xf520"' \
      --replace 'running = "⏵"' 'running = "\xf04b"' \
      --replace 'done = "✔"' 'done = "\xf00c"' \
      --replace 'todo = "⏸"' 'todo = "\xf04d"' \
      --replace 'warning = "⚠"' 'warning = "\xf071"' \
      --replace 'average = "∅"' 'average = "\xf1da"' \
      --replace 'bigsum = "∑"' 'bigsum = "\xf04a0"'
  '';
})
