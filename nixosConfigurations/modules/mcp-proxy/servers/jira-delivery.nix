{ pkgs, ... }:
let
  wrapper = pkgs.writeShellScriptBin "jira-mcp-delivery" ''
    export JIRA_URL="$JIRA_DTS_URL"
    export JIRA_USERNAME="$JIRA_EMAIL"
    export CONFLUENCE_URL="$JIRA_DTS_URL/wiki"
    export CONFLUENCE_USERNAME="$JIRA_EMAIL"
    export CONFLUENCE_API_TOKEN="$JIRA_API_TOKEN"
    exec ${pkgs.pkgs-mine.mcp-atlassian}/bin/mcp-atlassian --transport stdio "$@"
  '';
in
{
  services.mcp-proxy.servers.jira-d = {
    command = "${wrapper}/bin/jira-mcp-delivery";
    packages = [
      wrapper
      pkgs.pkgs-mine.mcp-atlassian
      pkgs.bashInteractive
    ];
    secretEnvVars = {
      JIRA_EMAIL = "jira/email";
      JIRA_API_TOKEN = "jira/api_token";
      JIRA_DTS_URL = "jira/dts_url";
    };
  };
}
