{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  useExecutor = true;

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
      "${pkgs.pkgs-mine.mcp-sse-client}/bin/mcp-sse-client"
      "https://mcp.lalala.casa/servers/${name}/sse"
    ];
    enabled = true;
  };

  mcpConfig =
    if useExecutor then
      {
        executor = {
          type = "remote";
          url = "https://executor.lalala.casa/mcp";
          enabled = true;
        };
      }
    else
      (
        pluginMcpServers
        // {
          slack = proxyServer "slack";
          nixos = proxyServer "nixos";
          chrome-devtools = proxyServer "chrome-devtools";
          jira-d = proxyServer "jira-d";
          jira-p = proxyServer "jira-p";
          discord = proxyServer "discord";
          outsmartly = {
            type = "remote";
            url = "http://localhost:3000/api/mcp";
            enabled = true;
          };
        }
      );
in
{
  programs.mcp.enableProxy = lib.mkForce (!useExecutor);

  programs.opencode = {
    enable = true;
    settings = {
      model = "anthropic/claude-sonnet-4-20250514";
      provider = {
        anthropic = { };
      };
      mcp = mcpConfig;
      plugin = [
        # "@ex-machina/opencode-anthropic-auth"
        # has auto-token refresh with keychain support
        "opencode-claude-auth@latest"
      ];
    };
    rules = # markdown
      ''
        # Xavier's Development Environment Rules
        ${lib.optionalString useExecutor ''
          ## MCP Executor Limitations

          **IMPORTANT**: When using the executor MCP endpoint, be aware that:
          - The executor MCP **only returns data** from function calls
          - `console.log()` and other console output **does NOT work**
          - Debug information, logs, and print statements will not be visible
          - Only the final return value/result will be available
          - Plan your debugging and information gathering accordingly
        ''}

        ## System Context
        - **praesidium**: Desktop tower (x86_64-linux, NVIDIA GPU)
        - **nox**: MacBook Air M3 (aarch64-darwin)
        - Uses Nix flakes with flake-parts, home-manager, and nix-darwin

        ## Development Guidelines
        - Always use `#!/usr/bin/env INTERPRETER` for script shebangs (required for NixOS)
        - Use `gh` CLI for GitHub access instead of fetch tools
        - Custom packages go in `packages/` with entry in `packages/default.nix`
        - Home-manager modules go in `home-manager/modules/`
      '';
  };

  # Skills from claude-plugins repo (relative symlinks resolve within nix store)
  xdg.configFile = {
    "opencode/skill/delivery-ticket-solver".source =
      "${claude-plugins-src}/delivery-ticket-solver/skills";
    "opencode/skill/product-ticket-solver".source =
      "${claude-plugins-src}/product-ticket-solver/skills";
  };
}
