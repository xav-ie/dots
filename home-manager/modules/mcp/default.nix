{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.mcp;

  # Slack MCP Server wrapper that injects secrets from sops
  slack-mcp-wrapper = pkgs.writeShellScriptBin "slack-mcp-server-wrapped" ''
    export SLACK_MCP_XOXC_TOKEN="$(cat /run/secrets/slack/xoxc_token)"
    export SLACK_MCP_XOXD_TOKEN="$(cat /run/secrets/slack/xoxd_token)"
    export SLACK_MCP_ADD_MESSAGE_TOOL=true
    exec ${pkgs.pkgs-mine.slack-mcp-server}/bin/slack-mcp-server "$@"
  '';

  # mcp-nixos package from flake input
  mcp-nixos = inputs.mcp-nixos.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.programs.mcp = {
    enableSlackWrapper = lib.mkEnableOption "Slack MCP server wrapper with sops secrets";
    enableNixos = lib.mkEnableOption "mcp-nixos server for NixOS/Home Manager assistance";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enableSlackWrapper {
      home.packages = [ slack-mcp-wrapper ];
    })
    (lib.mkIf cfg.enableNixos {
      home.packages = [ mcp-nixos ];
    })
  ];
}
