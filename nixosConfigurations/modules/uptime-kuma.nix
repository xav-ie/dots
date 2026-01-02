{ config, ... }:
let
  dataDir = "/media/uptime-kuma";
  inherit (config.services.local-networking) baseDomain;
  subdomain = "uptime";
  fullHostName = "${subdomain}.${baseDomain}";
in
{
  config = {
    services.local-networking.subdomains = [ subdomain ];

    virtualisation.oci-containers.containers.${subdomain} = {
      image = "louislam/uptime-kuma:2";
      volumes = [
        "${dataDir}:/app/data"
      ];
      labels = {
        "traefik.enable" = "true";
        # --- Router for HTTPS ---
        "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
        "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
        "traefik.http.routers.${subdomain}-secure.tls" = "true";
        "traefik.http.routers.${subdomain}-secure.tls.certResolver" = "cloudflare";
        "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
        # --- Service Definition ---
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = "3001";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 root root -"
    ];
  };
}
