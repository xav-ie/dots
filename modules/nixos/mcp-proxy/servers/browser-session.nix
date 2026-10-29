{
  flake.modules.nixos.praesidium =
    { config, pkgs, ... }:
    let
      inherit (config.services.local-networking) baseDomain;
      bs = config.services.browser-session;
      inherit (bs) stateDir;
      chromeHost = "${bs.chrome.subdomain}.${baseDomain}";
    in
    {
      # Uncomment once the secret exists (`sops secrets/main.yaml`):
      #   browser-session:
      #     typesafe_api_key: <key from console.typesafe.ai>
      # Until then jev: selectors just fail closed with "needs a TypeSafe API
      # key" and CSS selectors keep working.
      # sops.secrets."browser-session/typesafe_api_key" = { };

      services.mcp-proxy.servers.browser-session = {
        command = "${pkgs.pkgs-mine.browser-session-mcp}/bin/browser-session";
        args = [ "mcp" ];
        packages = [ pkgs.pkgs-mine.browser-session-mcp ];
        envVars = {
          BROWSER_URL = "https://${chromeHost}";
          # Every path (state.json, logs/, states/, takeover/) derives from this;
          # shared with the host-side daemons via the volume below.
          STATE_DIR = stateDir;
          # Public takeover URL to hand the user. The MCP only embeds it; it
          # never connects.
          TAKEOVER_BASE_URL = "https://${bs.takeover.subdomain}.${baseDomain}";
        };
        # Powers `jev:` selectors (click/type/press_key): the Jev decision
        # model picks the element. Same line as above, uncomment together:
        # secretEnvVars.TYPESAFE_API_KEY = "browser-session/typesafe_api_key";
        # Share state.json + logs/ (created by the browser-session module) with the
        # host-side reaper and listener.
        volumes = [ "${stateDir}:${stateDir}" ];
        extraHosts = [ "${chromeHost}:host-gateway" ];
      };
    };
}
