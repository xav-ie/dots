{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.claude;

  # The update script package
  inherit (pkgs.pkgs-mine) claude-code-update;

  # Native binary wrapper
  claude-native = pkgs.writeShellScriptBin "claude-native" ''
    export PATH="${config.home.homeDirectory}/.local/bin:$PATH"
    exec ${lib.getExe pkgs.pkgs-mine.claude-code} "$@"
  '';

  # NPM-based binary wrapper
  claude-npm = pkgs.writeShellScriptBin "claude-npm" ''
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
    ];

    home.file.".local/bin/claude" = {
      source = "${claude-package}/bin/claude";
    };

    home.file.".claude/settings.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/settings.json";
    home.file.".claude/notify.nu".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/notify.nu";
    home.file.".claude/statusline.nu".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/statusline.nu";
    home.file.".claude/marketplaces.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/marketplaces.json";
    home.file.".claude/setup-plugins.nu".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/setup-plugins.nu";
    home.file.".mcp.json".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/mcp.json";
    home.file.".claude/agents".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/agents";
    home.file.".claude/CLAUDE.md".source =
      config.lib.file.mkOutOfStoreSymlink "${config.dotFilesDir}/home-manager/modules/claude/CLAUDE.md";

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
