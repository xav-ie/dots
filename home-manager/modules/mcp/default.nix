{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mcp;
in
{
  options.programs.mcp = {
    enableProxy = lib.mkEnableOption "MCP SSE client for connecting to the containerized proxy";

    proxyUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://mcp.lalala.casa";
      description = "Base URL of the containerized MCP proxy";
    };
  };

  config = lib.mkIf cfg.enableProxy {
    home.packages = [
      pkgs.pkgs-mine.mcp-sse-client
    ];
  };
}
