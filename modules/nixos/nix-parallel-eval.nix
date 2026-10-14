{ inputs, ... }:
{
  flake.modules.nixos.linux =
    { pkgs, ... }:
    {
      nix.package = inputs.nix-src.packages.${pkgs.stdenv.hostPlatform.system}.default;
      # 0 = all cores; #572 only parallelizes when this is above 1.
      nix.settings.eval-cores = 0;
    };
}
