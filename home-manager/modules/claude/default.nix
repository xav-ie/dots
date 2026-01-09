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

  # Native binary from the custom package
  claude-native = pkgs.symlinkJoin {
    name = "claude-wrapped";
    paths = [ pkgs.pkgs-mine.claude-code ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --prefix PATH : "${config.home.homeDirectory}/.local/bin"
    '';
  };

  # NPM-based installation - use the package from packages/claude-code/npm.nix
  claude-npm = pkgs.pkgs-mine.claude-code-npm;

  claude-package = if cfg.nativeInstall then claude-native else claude-npm;

  # Slack MCP Server wrapper that injects secrets from sops
  slack-mcp-wrapper = pkgs.writeShellScriptBin "slack-mcp-server-wrapped" ''
    export SLACK_MCP_XOXC_TOKEN="$(cat /run/secrets/slack/xoxc_token)"
    export SLACK_MCP_XOXD_TOKEN="$(cat /run/secrets/slack/xoxd_token)"
    export SLACK_MCP_ADD_MESSAGE_TOOL=true
    exec ${pkgs.pkgs-mine.slack-mcp-server}/bin/slack-mcp-server "$@"
  '';

  # Wrapper script that calls the nu setup script
  pluginSetupScript = pkgs.writeShellScriptBin "claude-setup-plugins" ''
    exec ${pkgs.nushell}/bin/nu ~/.claude/setup-plugins.nu --config ~/.claude/marketplaces.json
  '';
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
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      claude-package
      inputs.mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default
      slack-mcp-wrapper
      pluginSetupScript
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
      command = "${pluginSetupScript}/bin/claude-setup-plugins";
      calendar = "daily";
      hour = 9;
      minute = 0;
    };
  };
}
