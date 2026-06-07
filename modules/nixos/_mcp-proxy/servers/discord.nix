{ pkgs, ... }:
{
  services.mcp-proxy.servers.discord = {
    command = "${pkgs.pkgs-mine.discord-mcp}/bin/discord-mcp";
    args = [ ];
    packages = [ pkgs.pkgs-mine.discord-mcp ];
    secretEnvVars = {
      DISCORD_USER_TOKEN = "discord/user_token";
    };
  };
}
