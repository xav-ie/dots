{ inputs, lib, ... }:
let
  claude-plugins-src = inputs.claude-marketplace-outsmartly;

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

  # Transform all MCP servers from plugins
  pluginMcpServers = lib.mapAttrs transformMcpServer mergedMcpServers;

  # Helper to define a containerized proxy MCP server
  proxyServer = name: {
    type = "local";
    command = [
      "mcp-sse-client"
      "https://mcp.lalala.casa/servers/${name}/sse"
    ];
    enabled = true;
  };
in
{
  # MCP SSE client for connecting to the containerized proxy
  programs.mcp.enableProxy = true;

  programs.opencode = {
    enable = true;
    settings = {
      model = "anthropic/claude-sonnet-4-20250514";
      provider = {
        anthropic = { };
      };
      # Plugin MCP servers are merged first, then our containerized proxy
      # definitions override any that share the same name (e.g. jira-d, jira-p)
      mcp = pluginMcpServers // {
        slack = proxyServer "slack";
        nixos = proxyServer "nixos";
        chrome-devtools = proxyServer "chrome-devtools";
        jira-d = proxyServer "jira-d";
        jira-p = proxyServer "jira-p";
      };
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
