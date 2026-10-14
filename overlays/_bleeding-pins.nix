# Package pins that ride on nixpkgs-bleeding. Applied by _bleeding.nix, and to
# the main set too while it shares bleeding's rev (see `bleedingInSync`).
#
# nushell 0.114.0 pulls in reedline 0.49.0, whose PR #1105 fixes scrollback
# pollution (prompt + tab-completions duplicated into the scrollback buffer
# when typing near the top of the pane). nixpkgs-bleeding
# is still on 0.113.1 (reedline 0.48.0). nu_plugin_prompt pins nu-plugin
# 0.114 to match — bump both together. Drop once nixpkgs packages >= 0.114.0.
final: prev: {
  nushell = prev.nushell.overrideAttrs (_old: rec {
    version = "0.114.0";
    src = final.fetchFromGitHub {
      owner = "nushell";
      repo = "nushell";
      tag = version;
      hash = "sha256-vLWfaci1lAPUXZJU2bfUvVNnMqFr6cMyX+R0aDWvRss=";
    };
    cargoDeps = final.rustPlatform.fetchCargoVendor {
      inherit src;
      name = "nushell-${version}-vendor";
      hash = "sha256-3+H1VuqdLxjcPTzkrpNiBmHbWG8g4rr3WuFFQhyyMtI=";
    };
  });
}
