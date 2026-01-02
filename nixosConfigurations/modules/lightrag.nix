{ config, ... }:
let
  dataDir = "/media/lightrag";
  inherit (config.services.local-networking) baseDomain;
  subdomain = "lightrag";
  fullHostName = "${subdomain}.${baseDomain}";
  cfgSecret = config.sops.placeholder;
in
{
  config = {
    sops = {
      secrets."lightrag/openai_api_key" = { };
      templates."lightrag.env" = {
        mode = "0440";
        content = ''
          LLM_BINDING=openai
          LLM_BINDING_API_KEY=${cfgSecret."lightrag/openai_api_key"}
          EMBEDDING_BINDING=openai
          EMBEDDING_BINDING_API_KEY=${cfgSecret."lightrag/openai_api_key"}
          LLM_MODEL=gpt-4o-mini
          EMBEDDING_MODEL=text-embedding-3-small
        '';
        restartUnits = [ "podman-${subdomain}.service" ];
      };
    };

    services.local-networking.subdomains = [ subdomain ];

    virtualisation.oci-containers.containers.${subdomain} = {
      image = "ghcr.io/hkuds/lightrag:latest";
      volumes = [
        "${dataDir}/rag_storage:/app/data/rag_storage"
        "${dataDir}/inputs:/app/data/inputs"
      ];
      environmentFiles = [
        config.sops.templates."lightrag.env".path
      ];
      extraOptions = [
        "--add-host=host.docker.internal:host-gateway"
      ];
      labels = {
        "traefik.enable" = "true";
        "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
        "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
        "traefik.http.routers.${subdomain}-secure.tls" = "true";
        "traefik.http.routers.${subdomain}-secure.tls.certResolver" = "cloudflare";
        "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = "9621";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 root root -"
      "d ${dataDir}/rag_storage 0755 root root -"
      "d ${dataDir}/inputs 0755 root root -"
    ];
  };
}
