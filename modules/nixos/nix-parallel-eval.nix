{ inputs, ... }:
{
  flake.modules.nixos.linux =
    { pkgs, ... }:
    {
      # nix-cli, not default: default also evaluates Nix's own test suites.
      nix.package = inputs.nix-src.packages.${pkgs.stdenv.hostPlatform.system}.nix-cli;
      # 0 = all cores; #572 only parallelizes when this is above 1.
      nix.settings.eval-cores = 0;
    };
}
