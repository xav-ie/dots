{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude;

  # Marketplace submodule (no cfg dependency - safe in outer let)
  marketplaceOpts = _: {
    options = {
      repo = lib.mkOption {
        type = lib.types.str;
        description = "GitHub repository in owner/repo format";
        example = "anthropics/claude-plugins-official";
      };

      src = lib.mkOption {
        type = lib.types.path;
        description = "Flake input source for the marketplace";
        example = "inputs.claude-marketplace-official";
      };
    };
  };

  # Find input name by matching src path against inputs (pure function, safe)
  findInputName =
    src: lib.findFirst (name: inputs.${name}.outPath or null == "${src}") null (lib.attrNames inputs);

in
{
  options.programs.claude = {
    enable = lib.mkEnableOption "Claude Code CLI";

    nativeInstall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to use the native (Bun-based) installation of Claude Code.

        When true: Uses the pre-compiled native binary (faster startup, but has known issues with editor integration).
        When false: Uses the npm/Node.js version (slower startup, but more reliable editor integration).

        Note: The native version has a known bug where it drops keystrokes in external editors (Ctrl+G).
        Using nativeInstall = false resolves this issue by using the npm installation instead.
      '';
    };

    pluginSyncPackage = lib.mkOption {
      type = lib.types.package;
      description = "The claude-plugin-sync package (default set in config when enabled)";
    };

    marketplaces = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule marketplaceOpts);
      default = {
        "claude-plugins-official" = {
          repo = "anthropics/claude-plugins-official";
          src = inputs.claude-marketplace-official;
        };
        "outsmartly-plugins" = {
          repo = "outsmartly/claude-plugins";
          src = inputs.claude-marketplace-outsmartly;
        };
        "claude-code-lsps" = {
          repo = "Piebald-AI/claude-code-lsps";
          src = inputs.claude-marketplace-lsps;
        };
        "Mixedbread-Grep" = {
          repo = "mixedbread-ai/mgrep";
          src = inputs.claude-marketplace-mgrep;
        };
      };
      description = "Claude Code marketplaces pinned from flake inputs";
      example = lib.literalExpression ''
        {
          "claude-plugins-official" = {
            repo = "anthropics/claude-plugins-official";
            src = inputs.claude-marketplace-official;
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      # Move all expensive computations inside mkIf so they're only evaluated when enabled

      # The update script package (in overlay)
      inherit (pkgs) claude-code-update;

      marketplaceInputNames = lib.filter (x: x != null) (
        lib.mapAttrsToList (_: m: findInputName m.src) cfg.marketplaces
      );

      updateMarketplacesPackage = pkgs.writeShellScriptBin "claude-update-marketplaces" ''
        cd "${config.dotFilesDir}"
        exec nix flake lock ${lib.concatMapStringsSep " " (i: "--update-input ${i}") marketplaceInputNames}
      '';

      # Generate known_marketplaces.json from configured marketplaces
      knownMarketplacesJson = builtins.toJSON (
        lib.mapAttrs (name: marketplace: {
          source = {
            source = "github";
            inherit (marketplace) repo;
          };
          installLocation = "${config.home.homeDirectory}/.claude/plugins/marketplaces/${name}";
          lastUpdated = "1970-01-01T00:00:00.000Z"; # Managed by Nix, not runtime updates
        }) cfg.marketplaces
      );

      # Generate home.file entries for marketplace directories
      marketplaceFiles = lib.mapAttrs' (name: marketplace: {
        name = ".claude/plugins/marketplaces/${name}";
        value = {
          source = marketplace.src;
        };
      }) cfg.marketplaces;

      # Native binary wrapper
      claude-native = pkgs.writeShellScriptBin "claude-native" ''
        export CLAUDE_CONFIG_DIR="$HOME/.claude"
        export PATH="${config.home.homeDirectory}/.local/bin:$PATH"
        exec ${pkgs.claude-code}/bin/claude "$@"
      '';

      # NPM-based binary wrapper (provides the claude-npm command name)
      claude-npm = pkgs.writeShellScriptBin "claude-npm" ''
        export CLAUDE_CONFIG_DIR="$HOME/.claude"
        exec ${pkgs.claude-code-npm}/bin/claude "$@"
      '';

      # Main 'claude' command pointing to the selected version
      selectedClaude =
        if cfg.nativeInstall then
          {
            pkg = claude-native;
            bin = "claude-native";
          }
        else
          {
            pkg = claude-npm;
            bin = "claude-npm";
          };

      claude-package = pkgs.writeShellScriptBin "claude" ''
        exec ${selectedClaude.pkg}/bin/${selectedClaude.bin} "$@"
      '';

      # Default plugin sync package (set via mkDefault below)
      defaultPluginSyncPackage = pkgs.writeNuApplication {
        name = "claude-plugin-sync";
        runtimeInputs = [ claude-package ];
        runtimeEnv = {
          CLAUDE_PLUGINS_CONFIG = "${config.dotFilesDir}/home-manager/modules/claude/marketplaces.json";
        };
        text = builtins.readFile ./setup-plugins.nu;
      };

      pluginSyncExe = "${cfg.pluginSyncPackage}/bin/claude-plugin-sync";
    in
    {
      # Set the default for pluginSyncPackage (can be overridden by user)
      programs.claude.pluginSyncPackage = lib.mkDefault defaultPluginSyncPackage;

      # MCP SSE client for connecting to the containerized proxy
      programs.mcp.enableProxy = true;

      home.activation.claudePluginSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        echo "Syncing claude plugins (background)..."
        ${pluginSyncExe} &>/dev/null &
        disown
      '';

      # Override plugin MCP configs to use the persistent proxy for instant startup.
      # This runs after plugin sync and rewrites .mcp.json in cached plugins to use
      # mcp-sse-client → proxy instead of slow direct mcp-remote connections.
      home.activation.claudePluginMcpOverride =
        lib.hm.dag.entryAfter [ "claudePluginSync" ] # sh
          ''
            _override_plugin_mcp() {
              local cache_dir="${config.home.homeDirectory}/.claude/plugins/cache"
              local proxy_url="${config.programs.mcp.proxyUrl}"

              for dir in "$cache_dir"/outsmartly-plugins/dts/*/  "$cache_dir"/outsmartly-plugins/pts/*/ ; do
                [ -d "$dir" ] || continue
                local mcp_file="$dir/.mcp.json"
                local plugin_name=$(basename "$(dirname "$(dirname "$dir")")")
                local server_name=$(basename "$(dirname "$dir")")

                # Map plugin directory name to proxy server name
                local proxy_name=""
                case "$server_name" in
                  dts) proxy_name="jira-d" ;;
                  pts) proxy_name="jira-p" ;;
                  *) continue ;;
                esac

                chmod u+w "$mcp_file" 2>/dev/null || true
                cat > "$mcp_file" <<MCPEOF
            {
              "mcpServers": {
                "$proxy_name": {
                  "command": "mcp-sse-client",
                  "args": ["$proxy_url/servers/$proxy_name/sse", "--strip-capabilities", "resources"]
                }
              }
            }
            MCPEOF
              done
            }
            _override_plugin_mcp
          '';

      home.packages = [
        claude-package
        claude-native
        claude-npm
        cfg.pluginSyncPackage
        updateMarketplacesPackage
      ]
      ++ lib.optionals pkgs.stdenv.isLinux [
        pkgs.pkgs-mine.claude-yolo
        pkgs.pkgs-mine.claude-overlay
      ];

      home.file = {
        ".local/bin/claude".source = "${claude-package}/bin/claude";
        ".claude/settings.json".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/settings.json";
        ".claude/notify.nu".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/notify.nu";
        ".claude/statusline.nu".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/statusline.nu";
        ".claude/marketplaces.json".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/marketplaces.json";
        ".claude/setup-plugins.nu".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/setup-plugins.nu";
        ".mcp.json".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/mcp.json";
        ".claude/agents".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/agents";
        ".claude/CLAUDE.md".source =
          config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/CLAUDE.md";
        ".claude/plugins/known_marketplaces.json".text = knownMarketplacesJson;
      }
      // marketplaceFiles;

      # Daily update check for claude-code sources
      services.scheduled.claude-code-update = {
        description = "Check for claude-code updates";
        command = "${claude-code-update}/bin/claude-code-update";
        workingDirectory = "${config.dotFilesDir}/packages/claude-code";
        calendar = "daily";
        hour = 9;
        minute = 0;
      };

      # Daily plugin sync - ensures marketplaces and plugins are installed
      services.scheduled.claude-plugin-sync = {
        description = "Sync Claude Code marketplaces and plugins";
        command = pluginSyncExe;
        calendar = "daily";
        hour = 9;
        minute = 0;
      };
    }
  );
}
