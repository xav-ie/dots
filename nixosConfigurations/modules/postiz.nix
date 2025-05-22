{ config, ... }:

let
  subdomain = "postiz";
  baseDomain = config.services.local-networking.baseDomain;
  fullHostName = "${subdomain}.${baseDomain}";

  postizDataDir = "/var/lib/postiz";
  postizJwtSecret = "!!CHANGE_ME_TO_A_VERY_LONG_RANDOM_SECRET_STRING!!";
  postgresUser = "${subdomain}-user";
  postgresPassword = "!!CHANGE_ME_TO_A_STRONG_POSTGRES_PASSWORD!!";
  postgresDB = "${subdomain}-db-local";
in
{
  config = {
    services.local-networking.subdomains = [ subdomain ];

    # Define the dedicated network for Postiz services
    virtualisation.oci-containers.networks."${subdomain}-network" = { };
    services.podman.networks."${subdomain}-network" = { };

    virtualisation.oci-containers.containers = {
      "${subdomain}-postgres" = {
        image = "postgres:17-alpine";
        containerName = "${subdomain}-postgres";
        autoStart = true;
        volumes = [
          "${postizDataDir}/postgres:/var/lib/postgresql/data"
        ];
        environment = {
          POSTGRES_PASSWORD = postgresPassword;
          POSTGRES_USER = postgresUser;
          POSTGRES_DB = postgresDB;
        };
        extraOptions = [ "--network=${subdomain}-network" ];
        healthcheck = {
          test = [
            "CMD-SHELL"
            "pg_isready -U ${postgresUser} -d ${postgresDB}"
          ];
          interval = "10s";
          timeout = "3s";
          retries = 3;
        };
      };

      "${subdomain}-redis" = {
        image = "redis:7.2";
        containerName = "${subdomain}-redis";
        autoStart = true;
        volumes = [
          "${postizDataDir}/redis:/data"
        ];
        extraOptions = [ "--network=${subdomain}-network" ];
        healthcheck = {
          test = [
            "CMD-SHELL"
            "redis-cli ping"
          ];
          interval = "10s";
          timeout = "3s";
          retries = 3;
        };
      };

      ${subdomain} = {
        # e.g., postiz
        image = "ghcr.io/gitroomhq/postiz-app:latest";
        containerName = subdomain;
        autoStart = true;
        dependsOn = [
          "${subdomain}-postgres"
          "${subdomain}-redis"
        ];
        extraOptions = [ "--network=${subdomain}-network" ];
        volumes = [
          "${postizDataDir}/config:/config/"
          "${postizDataDir}/uploads:/uploads/"
        ];
        environment = {
          # Core environment variables
          MAIN_URL = "https://${fullHostName}";
          FRONTEND_URL = "https://${fullHostName}";
          NEXT_PUBLIC_BACKEND_URL = "https://${fullHostName}/api";
          JWT_SECRET = postizJwtSecret;
          DATABASE_URL = "postgresql://${postgresUser}:${postgresPassword}@postiz-postgres:5432/${postgresDB}";
          REDIS_URL = "redis://postiz-redis:6379";
          BACKEND_INTERNAL_URL = "http://localhost:3000";
          IS_GENERAL = "true";
          STORAGE_PROVIDER = "local";
          UPLOAD_DIRECTORY = "/uploads";
          NEXT_PUBLIC_UPLOAD_DIRECTORY = "/uploads";

          # OPENAI_API_KEY = null;
          # X_API_KEY = null;
          # X_API_SECRET = null;
          # DISCORD_CLIENT_ID = null;
          # DISCORD_CLIENT_SECRET = null;
          # DISCORD_BOT_TOKEN_ID = null;
          # YOUTUBE_CLIENT_ID = null;
          # YOUTUBE_CLIENT_SECRET = null;
        };
        labels = {
          "traefik.enable" = "true";
          "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
          "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
          "traefik.http.routers.${subdomain}-secure.tls" = "true";
          "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";

          "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = "5000";
        };
      };
    };

    systemd.tmpfiles.rules = [
      "d ${postizDataDir} 0755 root root -"
      "d ${postizDataDir}/postgres 0700 root root -"
      "d ${postizDataDir}/redis 0700 root root -"
      "d ${postizDataDir}/config 0755 root root -"
      "d ${postizDataDir}/uploads 0755 root root -"
    ];
  };
}
