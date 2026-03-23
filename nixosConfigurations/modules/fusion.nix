{ config, ... }:
let
  dataDir = "/media/fusion";
  inherit (config.services.local-networking) baseDomain;
  subdomain = "fusion";
  fullHostName = "${subdomain}.${baseDomain}";
  cfgSecret = config.sops.placeholder;
in
{
  config = {
    sops = {
      secrets."fusion/password" = { };
      templates."fusion.env" = {
        mode = "0440";
        content = ''
          FUSION_PASSWORD=${cfgSecret."fusion/password"}
        '';
        restartUnits = [ "podman-${subdomain}.service" ];
      };
    };

    services.local-networking.subdomains = [ subdomain ];

    virtualisation.oci-containers.containers.${subdomain} = {
      image = "ghcr.io/0x2e/fusion:latest";
      environmentFiles = [ config.sops.templates."fusion.env".path ];
      environment = {
        FUSION_DB_PATH = "/data/fusion.db";
        FUSION_PORT = "8080";
        FUSION_LOG_LEVEL = "INFO";
        FUSION_ALLOW_PRIVATE_FEEDS = "true";
        FUSION_PULL_TIMEOUT = "60";
        FUSION_FEVER_USERNAME = "fusion";
      };
      volumes = [
        "${dataDir}:/data"
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
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = "8080";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 root root -"
    ];
  };
}
