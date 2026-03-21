{ config, pkgs, ... }:
let
  inherit (config.services.local-networking) baseDomain;

  # chrome-devtools-mcp: zero-dependency Node.js MCP server for Chrome DevTools
  chrome-devtools-mcp = pkgs.stdenvNoCC.mkDerivation {
    pname = "chrome-devtools-mcp";
    version = "0.16.0";
    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/chrome-devtools-mcp/-/chrome-devtools-mcp-0.16.0.tgz";
      hash = "sha256-k+qL5F29a5ex+5nLtL0v/LLyDXplAnvOb9ukVIRDLBw=";
    };
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p $out/lib/chrome-devtools-mcp
      cp -r . $out/lib/chrome-devtools-mcp/
      runHook postInstall
    '';
  };
in
{
  services.mcp-proxy.servers.chrome-devtools = {
    command = "${pkgs.nodejs}/bin/node";
    args = [
      "${chrome-devtools-mcp}/lib/chrome-devtools-mcp/build/src/index.js"
      "--browserUrl"
      "https://chrome.${baseDomain}"
    ];
    packages = [
      chrome-devtools-mcp
      pkgs.nodejs
    ];
    extraHosts = [ "chrome.${baseDomain}:host-gateway" ];
  };
}
