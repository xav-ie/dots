# Canonical constructor for the nixpkgs-bleeding package set.
#
# EVERY consumer of nixpkgs-bleeding goes through this — overlays/default.nix's
# `mkBleeding` (→ home-manager's `pkgs.pkgs-bleeding` + the CUDA variant),
# flake/packages.nix (→ tmux-shell's interactive nu + nu_plugin_prompt's build),
# and flake/devshell.nix (→ the direnv `nix develop` nu). Pinning here rather
# than at each call site is what keeps them from drifting onto different nushell
# builds, which breaks the plugin protocol handshake across a minor mismatch.
{
  nixpkgs-bleeding,
  system,
  config ? { },
  overlays ? [ ],
}:
import nixpkgs-bleeding {
  inherit system;
  config = {
    allowUnfree = true;
  }
  // config;
  overlays = [
    # nushell 0.114.0 pulls in reedline 0.49.0, whose PR #1105 fixes the tmux
    # scrollback pollution (prompt + tab-completions duplicated into the
    # scrollback buffer when typing near the top of the pane). nixpkgs-bleeding
    # is still on 0.113.1 (reedline 0.48.0). nu_plugin_prompt pins nu-plugin
    # 0.114 to match — bump both together. Drop once nixpkgs packages >= 0.114.0.
    (final: prev: {
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
    })
  ]
  ++ overlays;
}
