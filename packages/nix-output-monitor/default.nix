{ fetchpatch, nix-output-monitor }:

# Custom nix-output-monitor with Nerd Font icons
# https://haseebmajid.dev/posts/2025-08-10-til-how-to-change-emojis-in-nh/
nix-output-monitor.overrideAttrs (old: {
  patches = old.patches or [ ] ++ [
    # Determinate Nix emits activity type 10113, which 2.2.0 rejects with a
    # ParseNixJSONMessageError per line. PR #321 skips unknown types; pinned to
    # its head commit. Drop once a nom release includes it.
    (fetchpatch {
      name = "nom-unknown-activity-types.patch";
      url = "https://github.com/maralorn/nix-output-monitor/compare/c40cb12...202f940f96360548dedfb3b9234f6f6f08a9a2ba.diff";
      relative = "nix-output-monitor";
      hash = "sha256-BL1qnop/ZiXdPmyhX1mnzQU5MXCHqYTNmwzOT7jg/ig=";
    })
  ];
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
