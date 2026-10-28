# Declarative TCC grants (security.tcc), from github:xav-ie/nix-darwin-tcc.
# The grants themselves are declared next to the apps they're for.
{
  flake.modules.darwin.macos =
    { config, inputs, ... }:
    {
      imports = [ inputs.nix-darwin-tcc.darwinModules.default ];
      security.tcc.user = config.defaultUser;
    };
}
