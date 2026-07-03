{ config, pkgs, ... }:
let
  inherit (config.services.local-networking) baseDomain;
  bs = config.services.browser-session;
  inherit (bs) stateDir;
  chromeHost = "${bs.chrome.subdomain}.${baseDomain}";
in
{
  services.mcp-proxy.servers.browser-session = {
    command = "${pkgs.pkgs-mine.browser-session-mcp}/bin/browser-session";
    args = [ "mcp" ];
    packages = [ pkgs.pkgs-mine.browser-session-mcp ];
    envVars = {
      BROWSER_URL = "https://${chromeHost}";
      STATE_FILE = "${stateDir}/state.json";
      LOGS_DIR = "${stateDir}/logs";
      # Human-takeover: where to drop tickets (shared with the host-side
      # browser-session takeover daemon via the volume below) and the public
      # URL to hand the user. The MCP only embeds this URL; it never connects.
      TAKEOVER_DIR = "${stateDir}/takeover";
      TAKEOVER_BASE_URL = "https://${bs.takeover.subdomain}.${baseDomain}";
    };
    # Share state.json + logs/ (created by the browser-session module) with the
    # host-side reaper and listener.
    volumes = [ "${stateDir}:${stateDir}" ];
    extraHosts = [ "${chromeHost}:host-gateway" ];
  };
}
