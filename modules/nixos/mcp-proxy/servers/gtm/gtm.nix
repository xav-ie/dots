{ inputs, ... }:
{
  # Colocated with the module: the server itself (_package.nix + stdio.ts) and
  # the one-off credential minter (auth.nu, built inline). They land in
  # `pkgs.pkgs-mine` like everything under ./packages, since that set *is*
  # `self.packages.<system>`.
  perSystem =
    { pkgs, writeNuApplication, ... }:
    {
      packages = {
        gtm-mcp = pkgs.callPackage ./_package.nix { src = inputs.gtm-mcp-src; };
        gtm-mcp-auth = writeNuApplication {
          name = "gtm-mcp-auth";
          runtimeInputs = [ pkgs.oauth2l ];
          text = ./auth.nu |> builtins.readFile;
        };
      };
    };

  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      inherit (pkgs.pkgs-mine) gtm-mcp;
    in
    {
      services.mcp-proxy.servers.gtm = {
        command = "${gtm-mcp}/bin/gtm-mcp";
        packages = [ gtm-mcp ];
        secretEnvVars = {
          GTM_CLIENT_ID = "gtm/client_id";
          GTM_CLIENT_SECRET = "gtm/client_secret";
          GTM_REFRESH_TOKEN = "gtm/refresh_token";
        };
      };
    };
}
