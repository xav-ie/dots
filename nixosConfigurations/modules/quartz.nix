{ config, pkgs, ... }:
let
  inherit (config.services.local-networking) baseDomain;
  subdomain = "quartz";
  fullHostName = "${subdomain}.${baseDomain}";
  inherit (config) defaultUser;
  quartzRepoPath = "/home/${defaultUser}/Projects/quartz";
in
{
  config = {
    services.local-networking.subdomains = [ subdomain ];

    # Ensure quartz repo exists before container starts
    systemd.services."${subdomain}-repo-init" = {
      description = "Initialize Quartz repository if missing";
      wantedBy = [ "multi-user.target" ];
      before = [ "podman-${subdomain}.service" ];
      requiredBy = [ "podman-${subdomain}.service" ];
      path = [ pkgs.gh ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = defaultUser;
      };
      script = ''
        if [ ! -d "${quartzRepoPath}/.git" ]; then
          echo "Quartz repo not found at ${quartzRepoPath}, cloning..."
          mkdir -p "$(dirname "${quartzRepoPath}")"
          gh repo clone xav-ie/quartz "${quartzRepoPath}"
        else
          echo "Quartz repo already exists at ${quartzRepoPath}"
        fi
      '';
    };

    virtualisation.oci-containers.containers.${subdomain} = {
      image = "node:22";
      volumes = [
        "${quartzRepoPath}:/quartz"
      ];
      workdir = "/quartz";
      cmd = [
        "npx"
        "quartz"
        "build"
        "--serve"
        "--port"
        "8085"
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
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = "8085";
      };
    };
  };
}
