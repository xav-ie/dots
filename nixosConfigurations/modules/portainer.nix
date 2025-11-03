{ config, ... }:
let
  portainerDir = "/media/portainer";
  inherit (config.services.local-networking) baseDomain;
  subdomain = "portainer";
  fullHostName = "${subdomain}.${baseDomain}";
in
{
  config = {
    services.local-networking.subdomains = [ subdomain ];

    virtualisation.oci-containers.containers.${subdomain} = {
      autoStart = false; # Only start when needed to reduce excessive API polling/logging
      image = "portainer/portainer-ce:latest";
      # You must access through traefik
      # ports = [ "9000:9000" "9443:9443" ];
      volumes = [
        "/var/run/docker.sock:/var/run/docker.sock"
        "${portainerDir}/portainer_data:/data"
      ];
      labels = {
        # expose the container to traefik
        "traefik.enable" = "true";
        # --- Router for HTTPS ---
        "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
        "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
        "traefik.http.routers.${subdomain}-secure.tls" = "true";
        "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
        # --- Service Definition ---
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = "9443";
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.scheme" = "https";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${portainerDir} 0755 100 1000 -"
      "d ${portainerDir}/portainer_data 0755 100 1000 -"
    ];
  };
}
