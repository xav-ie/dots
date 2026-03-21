{
  config,
  ...
}:
let
  inherit (config.services.local-networking) baseDomain;
  subdomain = "chrome";
  fullHostName = "${subdomain}.${baseDomain}";
  containerPort = 3000; # browserless internal port
  chromeDataDir = "/var/lib/chrome";
in
{
  config = {
    services.local-networking.subdomains = [ subdomain ];

    virtualisation.oci-containers.containers.${subdomain} = {
      autoStart = true;
      image = "browserless/chrome:latest";
      environment = {
        # Timeout for each browser session (ms). 0 = no timeout.
        TIMEOUT = "0";
        # Max parallel browser sessions
        CONCURRENT = "10";
        # Enable the DevTools debugger UI
        ENABLE_DEBUGGER = "true";
        # Enable health endpoint
        HEALTH = "true";
        # Persist browser profile data (cookies, sessions, etc.)
        DATA_DIR = "/data";
      };
      volumes = [
        "/dev/shm:/dev/shm"
        "${chromeDataDir}:/data"
      ];
      extraOptions = [ "--shm-size=2g" ];
      labels = {
        # Expose the container to traefik
        "traefik.enable" = "true";
        # --- Router for HTTPS ---
        "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
        "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
        "traefik.http.routers.${subdomain}-secure.tls" = "true";
        "traefik.http.routers.${subdomain}-secure.tls.certResolver" = "cloudflare";
        "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
        # --- Service Definition ---
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = toString containerPort;
      };
    };

    systemd.tmpfiles.rules = [
      "d ${chromeDataDir} 0755 root root -"
    ];
  };
}
