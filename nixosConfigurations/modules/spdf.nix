{ config, ... }:
let
  spdfFolder = "/media/spdf";
  inherit (config.services.local-networking) baseDomain;
  subdomain = "spdf";
  fullHostName = "${subdomain}.${baseDomain}";
in
{
  config = {
    services.local-networking.subdomains = [ subdomain ];

    virtualisation.oci-containers.containers.${subdomain} = {
      autoStart = true;
      # https://github.com/Stirling-Tools/Stirling-PDF/releases
      image = "ghcr.io/stirling-tools/stirling-pdf:0.46.1-fat";
      environment = {
        PUID = "1000";
        PGID = "100";
        UMASK = "022";
        SECURITY_ENABLE_LOGIN = "false";
        SECURITY_CSRF_DISABLED = "false";
        SYSTEM_DEFAULT_LOCALE = "en-US";
        METRICS_ENABLED = "false";
      };
      # access through traefik
      # ports = [ "8071:8080" ];
      volumes = [ "${spdfFolder}:/configs" ];
      labels = {
        "traefik.enable" = "true";
        # --- Router for HTTPS ---
        "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
        "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
        "traefik.http.routers.${subdomain}-secure.tls" = "true";
        "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
        # --- Service Definition ---
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = "8080";
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.scheme" = "http";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${spdfFolder} 0755 100 1000 -"
    ];
  };
}
