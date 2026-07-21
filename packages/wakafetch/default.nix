# Terminal dashboard for WakaTime/Wakapi coding activity. Reads the shared
# ~/.wakatime.cfg (api_key + api_url, rendered by modules/wakatime.nix), so it
# talks to our self-hosted wakapi out of the box. `wakafetch --daily`,
# `--heatmap`, `--no-colors`. Pure Go, no external deps (vendorHash = null);
# bump `rev` + `hash` together from GitHub.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
  fetchpatch,
}:
buildGoModule {
  pname = "wakafetch";
  version = "0-unstable-2026-07-20";

  src = fetchFromGitHub {
    owner = "sahaj-b";
    repo = "wakafetch";
    rev = "9adc20e10e87d1ad53e22a1ef94c9df326ccf0c2";
    hash = "sha256-u78bftzwoNxsLz91SFnAPwnPQ6++52cxk/6WwK8PdLc=";
  };

  patches = [
    # PR #5: treat any non-api.wakatime.com host as wakapi and append the
    # /compat/wakatime path so /summaries (--daily/--heatmap/--days) resolves.
    # Lets modules/wakatime.nix keep api_url at plain /api. Drop once merged.
    (fetchpatch {
      url = "https://github.com/sahaj-b/wakafetch/pull/5.diff";
      hash = "sha256-5sMFA6mZNOj9dX1+qNstgM+3I5Nh1p/dp9TeJLZVn1A=";
    })
    # PR #8 (ours): stop double-counting rightPad in the card bottom border,
    # which overshot the right edge in the --full layout. Drop once merged.
    (fetchpatch {
      url = "https://github.com/sahaj-b/wakafetch/pull/8.diff";
      hash = "sha256-tUBNBiQj3pvxHmA3hDMateUkXkzOzHstEB9VnjwLpus=";
    })
  ];

  vendorHash = null;

  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Terminal dashboard for your WakaTime/Wakapi coding activity";
    homepage = "https://github.com/sahaj-b/wakafetch";
    license = lib.licenses.mit;
    mainProgram = "wakafetch";
  };
}
