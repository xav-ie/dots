{ config, pkgs, ... }:
let
  inherit (config.services.local-networking) baseDomain;
  browserURL = "https://${config.services.chrome-headless.subdomain}.${baseDomain}";
  stateDir = "/var/lib/browser-session-mcp";
in
{
  services.mcp-proxy.servers.browser-session = {
    command = "${pkgs.pkgs-mine.browser-session-mcp}/bin/browser-session-mcp";
    args = [ ];
    packages = [ pkgs.pkgs-mine.browser-session-mcp ];
    envVars = {
      BROWSER_URL = browserURL;
      STATE_FILE = "${stateDir}/state.json";
      LOGS_DIR = "${stateDir}/logs";
    };
    # Share state.json + logs/ with the host-side reaper and listener.
    volumes = [ "${stateDir}:${stateDir}" ];
    extraHosts = [ "${config.services.chrome-headless.subdomain}.${baseDomain}:host-gateway" ];
  };

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0755 root root - -"
    "d ${stateDir}/logs 0755 root root - -"
    # Cookies and session tokens — keep readable by root only.
    "d ${stateDir}/states 0700 root root - -"
  ];
}
