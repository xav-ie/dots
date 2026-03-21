{ inputs, pkgs, ... }:
let
  mcp-nixos = inputs.mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  services.mcp-proxy.servers.nixos = {
    command = "${mcp-nixos}/bin/mcp-nixos";
    packages = [ mcp-nixos ];
  };
}
