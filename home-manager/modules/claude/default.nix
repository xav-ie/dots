{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude;

  # The update script package
  inherit (pkgs.pkgs-mine) claude-code-update;

  # Marketplace submodule
  marketplaceOpts =
    _:
    {
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

  # Find input name by matching src path against inputs
  findInputName =
    src:
    lib.findFirst (name: inputs.${name}.outPath or null == "${src}") null (lib.attrNames inputs);

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
    export PATH="${config.home.homeDirectory}/.local/bin:$PATH"
    exec ${lib.getExe pkgs.pkgs-mine.claude-code} "$@"
  '';

  # NPM-based binary wrapper
  claude-npm = pkgs.writeShellScriptBin "claude-npm" ''
    export DISABLE_INSTALLATION_CHECKS=1
    exec ${lib.getExe pkgs.pkgs-mine.claude-code-npm} "$@"
  '';

  # Main 'claude' command pointing to the selected version
  claude-package = pkgs.writeShellScriptBin "claude" ''
    exec ${lib.getExe (if cfg.nativeInstall then claude-native else claude-npm)} "$@"
  '';

  # Wrapper script that calls the nu setup script
  defaultPluginSyncPackage = pkgs.writeNuApplication {
    name = "claude-plugin-sync";
    runtimeInputs = [ claude-package ];
    runtimeEnv = {
      CLAUDE_PLUGINS_CONFIG = "${config.dotFilesDir}/home-manager/modules/claude/marketplaces.json";
    };
    text = builtins.readFile ./setup-plugins.nu;
  };
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
      default = defaultPluginSyncPackage;
      description = "The claude-plugin-sync package";
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
        "meta-cc-marketplace" = {
          repo = "yaleh/meta-cc";
          src = inputs.claude-marketplace-meta-cc;
        };
        "beads-marketplace" = {
          repo = "steveyegge/beads";
          src = inputs.claude-marketplace-beads;
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

  config = lib.mkIf cfg.enable {
    # Enable shared MCP servers
    programs.mcp.enableSlackWrapper = true;
    programs.mcp.enableNixos = true;

    home.activation.claudePluginSync = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      echo "Syncing claude plugins..."
      run ${lib.getExe cfg.pluginSyncPackage} || true
    '';

    home.packages = [
      claude-package
      claude-native
      claude-npm
      cfg.pluginSyncPackage
      updateMarketplacesPackage
    ];

    home.file =
      {
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
      command = lib.getExe cfg.pluginSyncPackage;
      calendar = "daily";
      hour = 9;
      minute = 0;
    };
  };
}
