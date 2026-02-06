{ pkgs }:
pkgs.buildGoModule {
  pname = "mcp-sse-client";
  version = "0.1.0";
  src = ./.;
  vendorHash = null; # No external dependencies
}
