{ pkgs, ... }:
let
  dataDir = "/var/lib/slack-mcp";
in
{
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 root root -"
  ];

  services.mcp-proxy.servers.slack = {
    command = "${pkgs.pkgs-mine.slack-mcp-server}/bin/slack-mcp-server";
    packages = [ pkgs.pkgs-mine.slack-mcp-server ];
    secretEnvVars = {
      SLACK_MCP_XOXC_TOKEN = "slack/xoxc_token";
      SLACK_MCP_XOXD_TOKEN = "slack/xoxd_token";
    };
    envVars = {
      SLACK_MCP_ADD_MESSAGE_TOOL = "true";
      SLACK_MCP_MARK_TOOL = "true";
      SLACK_MCP_CHANNELS_CACHE = "${dataDir}/channels.cache";
      SLACK_MCP_USERS_CACHE = "${dataDir}/users.cache";
    };
    volumes = [
      "${dataDir}:${dataDir}"
    ];
  };
}
