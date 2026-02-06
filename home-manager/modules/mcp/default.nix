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

  # Port for the persistent MCP proxy
  defaultProxyPort = 18199;

  # Build the named-server-config JSON from enabled servers
  proxyServersConfig = pkgs.writeText "mcp-proxy-servers.json" (
    builtins.toJSON {
      mcpServers = lib.filterAttrs (_: v: v != null) cfg.proxyServers;
    }
  );
in
{
  options.programs.mcp = {
    enableSlackWrapper = lib.mkEnableOption "Slack MCP server wrapper with sops secrets";
    enableNixos = lib.mkEnableOption "mcp-nixos server for NixOS/Home Manager assistance";
    enableProxy = lib.mkEnableOption "persistent MCP proxy for instant startup";

    proxyPort = lib.mkOption {
      type = lib.types.port;
      default = defaultProxyPort;
      description = "Port for the persistent MCP proxy";
    };

    proxyServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.nullOr lib.types.attrs);
      default = { };
      description = "MCP servers to run behind the persistent proxy";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enableSlackWrapper {
      home.packages = [ slack-mcp-wrapper ];
      programs.mcp.proxyServers.slack = lib.mkDefault {
        command = "${slack-mcp-wrapper}/bin/slack-mcp-server-wrapped";
        args = [ ];
      };
    })
    (lib.mkIf cfg.enableNixos {
      home.packages = [ mcp-nixos ];
      programs.mcp.proxyServers.nixos = lib.mkDefault {
        command = "${mcp-nixos}/bin/mcp-nixos";
        args = [ ];
      };
    })
    (lib.mkIf cfg.enableProxy {
      home.packages = [
        pkgs.mcp-proxy
        pkgs.pkgs-mine.mcp-sse-client
      ];

      # Persistent systemd user service
      systemd.user.services.mcp-proxy = {
        Unit = {
          Description = "Persistent MCP proxy server";
          After = [ "sops-nix.service" ];
        };
        Service = {
          ExecStart = builtins.concatStringsSep " " [
            "${pkgs.mcp-proxy}/bin/mcp-proxy"
            "--port=${toString cfg.proxyPort}"
            "--pass-environment"
            "--named-server-config"
            "${proxyServersConfig}"
          ];
          Restart = "on-failure";
          RestartSec = 5;
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };
    })
  ];
}
