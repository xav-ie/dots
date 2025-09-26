{
  config,
  inputs,
  pkgs,
  ...
}:

let
  subdomain = "postiz";
  inherit (config.services.local-networking) baseDomain;
  fullHostName = "${subdomain}.${baseDomain}";

  postizDataDir = "/var/lib/postiz";
  postgresUser = "${subdomain}-user";
  postgresDB = "${subdomain}-db-local";

  # UID/GID of postgres user inside postgres:17-alpine container
  # To verify/update: podman run --rm postgres:17-alpine id postgres
  # Alpine Linux uses UID 70 as the standard for the postgres system user
  postgresUID = "70";
  postgresGID = "70";

  # UID/GID of redis user inside redis:7.2 container
  # To verify/update: podman run --rm redis:7.2 id redis
  redisUID = "999";
  redisGID = "999";

  cfgSecret = config.sops.placeholder;

  # Fetch and patch the Postiz source
  postizSrc = pkgs.stdenv.mkDerivation {
    name = "postiz-src-patched";
    src = pkgs.fetchFromGitHub {
      owner = "gitroomhq";
      repo = "postiz-app";
      rev = "v2.7.0";
      sha256 = "sha256-6Xjmui5Y+wPVgQAIcHLMyG4mikujQSk2bqRrDI7uz2E=";
    };
    patches = [ ./postiz-integration-fix.patch ];
    phases = [
      "unpackPhase"
      "patchPhase"
      "installPhase"
    ];
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };
in
{
  imports = [ inputs.quadlet-nix.nixosModules.quadlet ];

  config = {
    # Systemd service to build the Docker image from patched source
    systemd.services."build-${subdomain}-image" = {
      description = "Build patched Docker image";
      wantedBy = [ "multi-user.target" ];
      before = [ "${subdomain}.service" ];
      path = with pkgs; [ podman ];

      script = ''
        # Build the Docker image using the patched source and Dockerfile.dev
        podman build -f ${postizSrc}/Dockerfile.dev -t localhost/postiz-app-patched:latest ${postizSrc}
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    sops = {
      secrets = {
        # internal
        "postiz/internal/jwt_secret" = { };
        "postiz/internal/postgres_password" = { };

        # linkedin
        "postiz/linkedin/client_id" = { };
        "postiz/linkedin/client_secret" = { };

        # mastodon
        "postiz/mastodon/client_id" = { };
        "postiz/mastodon/client_secret" = { };

        # x
        "postiz/x/api_key" = { };
        "postiz/x/api_key_secret" = { };
      };
      templates."postiz.env" = {
        mode = "0440";
        content =
          # sh
          ''
            # internal
            JWT_SECRET=${cfgSecret."postiz/internal/jwt_secret"}
            DATABASE_URL=postgresql://${postgresUser}:${
              cfgSecret."postiz/internal/postgres_password"
            }@${subdomain}-postgres:5432/${postgresDB}

            # mastodon
            MASTODON_CLIENT_ID=${cfgSecret."postiz/mastodon/client_id"}
            MASTODON_CLIENT_SECRET=${cfgSecret."postiz/mastodon/client_secret"}
            MASTODON_URL=https://mastodon.social

            # linkedin
            LINKEDIN_CLIENT_ID=${cfgSecret."postiz/linkedin/client_id"}
            LINKEDIN_CLIENT_SECRET=${cfgSecret."postiz/linkedin/client_secret"}

            # x
            X_API_KEY=${cfgSecret."postiz/x/api_key"}
            X_API_SECRET=${cfgSecret."postiz/x/api_key_secret"}
          '';
        restartUnits = [ "${subdomain}.service" ];
      };
      templates."postgres.env" = {
        mode = "0440";
        content = # sh
          ''
            POSTGRES_PASSWORD=${cfgSecret."postiz/internal/postgres_password"};
          '';
        restartUnits = [ "${subdomain}-postgres.service" ];
      };
    };

    services.local-networking.subdomains = [ subdomain ];

    virtualisation.quadlet =
      let
        inherit (config.virtualisation.quadlet) pods;
      in
      {
        networks."${subdomain}-network".networkConfig = { };

        pods."${subdomain}-pod" = {
          podConfig = {
            addHosts = [ "${fullHostName}:192.168.1.158" ];
          };
        };

        containers = {
          "${subdomain}-postgres" = {
            containerConfig = {
              image = "postgres:17-alpine";
              pod = pods."${subdomain}-pod".ref;
              volumes = [
                "${postizDataDir}/postgres:/var/lib/postgresql/data"
              ];
              environmentFiles = [ config.sops.templates."postgres.env".path ];
              environments = {
                POSTGRES_USER = postgresUser;
                POSTGRES_DB = postgresDB;
              };
              healthCmd = "pg_isready -U ${postgresUser} -d ${postgresDB}";
              healthInterval = "10s";
              healthTimeout = "3s";
              healthRetries = 3;
            };
            serviceConfig = {
              Restart = "always";
            };
          };

          "${subdomain}-redis" = {
            containerConfig = {
              image = "redis:7.2";
              pod = pods."${subdomain}-pod".ref;
              volumes = [
                "${postizDataDir}/redis:/data"
              ];
              healthCmd = "redis-cli ping";
              healthInterval = "10s";
              healthTimeout = "3s";
              healthRetries = 3;
            };
            serviceConfig = {
              Restart = "always";
            };
          };

          ${subdomain} = {
            containerConfig = {
              image = "localhost/postiz-app-patched:latest";
              # Disabled since we build locally for now
              # image = "ghcr.io/gitroomhq/postiz-app:latest";
              # autoUpdate = "registry";
              pod = pods."${subdomain}-pod".ref;
              volumes = [
                "${postizDataDir}/config:/config/"
                "${postizDataDir}/uploads:/uploads/"
              ];
              environmentFiles = [ config.sops.templates."postiz.env".path ];
              environments = {
                MAIN_URL = "https://${fullHostName}";
                FRONTEND_URL = "https://${fullHostName}";
                NEXT_PUBLIC_BACKEND_URL = "https://${fullHostName}/api";
                REDIS_URL = "redis://localhost:6379";
                BACKEND_INTERNAL_URL = "http://localhost:3000";
                IS_GENERAL = "true";
                STORAGE_PROVIDER = "local";
                UPLOAD_DIRECTORY = "/uploads";
                NEXT_PUBLIC_UPLOAD_DIRECTORY = "/uploads";
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
            serviceConfig = {
              Restart = "always";
            };
            unitConfig = {
              After = [
                "${subdomain}-postgres.service"
                "${subdomain}-redis.service"
              ];
              Requires = [
                "${subdomain}-postgres.service"
                "${subdomain}-redis.service"
              ];
            };
          };
        };
      };

    systemd.tmpfiles.rules = [
      "d ${postizDataDir} 0755 root root -"
      "d ${postizDataDir}/postgres 0700 ${postgresUID} ${postgresGID} -"
      "d ${postizDataDir}/redis 0755 ${redisUID} ${redisGID} -"
      "d ${postizDataDir}/config 0755 root root -"
      "d ${postizDataDir}/uploads 0755 root root -"
    ];
  };
}
