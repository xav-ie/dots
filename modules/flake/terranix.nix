# Wire terranix so `./_arca-infra.nix` becomes runnable OpenTofu:
#   nix run .#arca-infra        # apply
#   nix run .#arca-infra.plan   # plan
#   nix run .#arca-infra.destroy
# Tokens are passed as TF_VAR_* (sourced from sops by `cachectl infra`).
{ inputs, ... }:
{
  imports = [ inputs.terranix.flakeModule ];

  perSystem =
    { pkgs, ... }:
    {
      terranix.terranixConfigurations.arca-infra = {
        modules = [ ./_arca-infra.nix ];
        terraformWrapper.package = pkgs.opentofu;
      };
    };
}
