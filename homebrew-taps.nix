{ config, ... }:
{
  # https://github.com/zhaofengli/nix-homebrew/issues/5
  # You must tell nix-darwin to just inherit the same taps as nix-homebrew
  homebrew.taps = builtins.attrNames config.nix-homebrew.taps;
}
