{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.gemini;
in
{
  options.programs.gemini = {
    enable = lib.mkEnableOption "Gemini CLI";
    # Add Gemini-specific options here, similar to claude module
  };

  config = lib.mkIf cfg.enable {
    # Here you'll define how to install gemini CLI and configure its MCP servers
    # For example, based on the previous .mcp.json and research:
    # - Configure mcp servers for Slack
    # - Potentially define a gemini CLI package

    # Example placeholder for MCP server configuration
    # programs.mcp.proxyServers.slack = {
    #   command = "your-slack-mcp-command";
    #   args = ["--your-args"];
    # };

    # Example for enabling gemini CLI if it's available in nixpkgs or needs custom setup
    # home.packages = [ pkgs.gemini-cli ]; # Or a custom derivation
  };
}
