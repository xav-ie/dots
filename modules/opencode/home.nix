{
  flake.modules.homeManager.common =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      useExecutor = true;

      claude-plugins-src = inputs.claude-marketplace-outsmartly;

      # Find all .mcp.json files in claude-plugins repo and merge their mcpServers
      mcpJsonFiles =
        lib.filesystem.listFilesRecursive claude-plugins-src |> lib.filter (f: lib.hasSuffix ".mcp.json" f);
      allMcpConfigs = map (f: f |> builtins.readFile |> builtins.fromJSON) mcpJsonFiles;
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
            # V2 `servers` shape: the V1 top-level form is normalized
            # without `codemode`
            servers.executor = {
              type = "remote";
              url = "https://executor.lalala.casa/mcp";
              # Executor is its own code mode; opencode only skips wrapping
              # executor.sh URLs by default, so opt this host out too
              codemode = false;
              headers = {
                Authorization = "Bearer {env:EXECUTOR_AUTH_TOKEN}";
                CF-Access-Client-Id = "{env:CF_ACCESS_CLIENT_ID}";
                CF-Access-Client-Secret = "{env:CF_ACCESS_CLIENT_SECRET}";
              };
            };
          }
        else
          (
            pluginMcpServers
            // {
              slack = proxyServer "slack";
              nixos = proxyServer "nixos";
              # chrome-devtools = proxyServer "chrome-devtools";
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
          # GLM via the z.ai coding plan; the key lives in opencode's own
          # credential store (`opencode auth login` → auth.json), so the
          # provider block stays empty here.
          model = "zai-coding-plan/glm-5.3";
          provider = {
            anthropic = { };
            "zai-coding-plan" = { };
          };
          mcp = mcpConfig;
          # V2 plugins key (V1 `plugin` is normalized, but be native). Both
          # npm entries publish V2 support; opencode-claude-auth is V1-only
          # and dropped (anthropic auth already lives in opencode's own
          # credential store). The two local shims below are auto-discovered
          # from ~/.config/opencode/plugins/.
          plugins = [
            # time tracking, opencode counterpart of claude-code-wakatime;
            # uses ~/.wakatime.cfg and the wakatime-cli already on PATH
            "opencode-wakatime"
            # dynamic context pruning, the context-mode counterpart: swaps
            # stale tool outputs for summaries/placeholders before each LLM
            # call, model-invoked compress tool, session history untouched
            "@tarquinen/opencode-dcp@latest"
          ];
        };
        context = # markdown
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
              - Executor apps (slack, browser-session, ...) are found with the executor MCP's own `search` tool and run with its `call`/`execute`; opencode's Code Mode catalog does not contain them
              - Executor's `skills` tool is not an app inventory (apps without skills are missing from it); never conclude an app is unlinked from it
            ''}

            ## System Context
            - **praesidium**: Desktop tower (x86_64-linux, NVIDIA GPU)
            - **nox**: MacBook Air M3 (aarch64-darwin)
            - Uses Nix flakes with flake-parts, home-manager, and nix-darwin

            ## Development Guidelines
            - Always use `#!/usr/bin/env INTERPRETER` for script shebangs (required for NixOS)
            - Use `gh` CLI for GitHub access instead of fetch tools
            - Custom packages go in `packages/` with entry in `packages/default.nix`
            - Config goes in a concern module under `modules/` (dendritic)
          '';
      };

      # Skills from claude-plugins repo (relative symlinks resolve within nix store)
      xdg.configFile = {
        "opencode/skill/delivery-ticket-solver".source =
          "${claude-plugins-src}/delivery-ticket-solver/skills";
        "opencode/skill/product-ticket-solver".source =
          "${claude-plugins-src}/product-ticket-solver/skills";

        # Vision shim: pasted images are described by glm-5.3-flash and the
        # description replaces the image part, so text-only coding models
        # (the rest of the coding plan) still accept them. Native vision
        # models are left untouched. Same live-editable deployment.
        "opencode/plugins/image-describe.ts".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/modules/opencode/image-describe.ts";
      };
    };
}
