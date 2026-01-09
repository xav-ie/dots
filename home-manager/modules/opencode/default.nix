{ inputs, lib, ... }:
let
  claude-plugins-src = inputs.claude-plugins;

  # Find all .mcp.json files in claude-plugins repo and merge their mcpServers
  mcpJsonFiles = lib.filter (f: lib.hasSuffix ".mcp.json" f) (
    lib.filesystem.listFilesRecursive claude-plugins-src
  );
  allMcpConfigs = map (f: builtins.fromJSON (builtins.readFile f)) mcpJsonFiles;
  mergedMcpServers = lib.foldl (acc: cfg: acc // (cfg.mcpServers or { })) { } allMcpConfigs;

  # Substitute ${CLAUDE_PLUGIN_ROOT} with nix store path
  substitutePluginRoot =
    str: builtins.replaceStrings [ "\${CLAUDE_PLUGIN_ROOT}" ] [ (toString claude-plugins-src) ] str;

  # Transform upstream MCP config to opencode format
  transformMcpServer = _name: server: {
    type = "local";
    command = [ (substitutePluginRoot server.command) ] ++ (server.args or [ ]);
    enabled = true;
  };

  # Transform all MCP servers
  pluginMcpServers = lib.mapAttrs transformMcpServer mergedMcpServers;
in
{
  # Enable shared MCP servers (slack wrapper and mcp-nixos packages)
  programs.mcp.enableSlackWrapper = true;
  programs.mcp.enableNixos = true;

  programs.opencode = {
    enable = true;
    settings = {
      model = "anthropic/claude-sonnet-4-20250514";
      provider = {
        anthropic = { };
      };
      mcp = {
        slack = {
          type = "local";
          command = [ "slack-mcp-server-wrapped" ];
          enabled = true;
        };
        nixos = {
          type = "local";
          command = [ "mcp-nixos" ];
          enabled = true;
        };
      }
      // pluginMcpServers;
    };
  };

  # Skills from claude-plugins repo (relative symlinks resolve within nix store)
  xdg.configFile = {
    "opencode/skill/delivery-ticket-solver".source =
      "${claude-plugins-src}/delivery-ticket-solver/skills";
    "opencode/skill/product-ticket-solver".source =
      "${claude-plugins-src}/product-ticket-solver/skills";
  };
}
