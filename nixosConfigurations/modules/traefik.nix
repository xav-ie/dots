{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.services.local-networking) baseDomain subdomains;

  allDomains = [
    baseDomain
  ] ++ (map (subdomain: "${subdomain}.${baseDomain}") subdomains);
  hostEntries = lib.concatStringsSep "\n" (
    map (d: ''
      127.0.0.1 ${d}
      ::1       ${d}
    '') allDomains
  );
  # TODO: simplify... this works for now
  mkcertCAHelper = pkgs.writeNuApplication {
    name = "mkcert-ca-helper";
    runtimeInputs = with pkgs; [
      mkcert
      nssTools
    ];
    text = # nu
      ''
        def main [out: string] {
          $env.CAROOT = $out
          mkdir $out
          mkcert -install out+err>| ignore
          mkcert -CAROOT
        }
      '';
  };
  mkcertCA =
    pkgs.runCommand "mkcertCA"
      {
        buildInputs = [
          mkcertCAHelper
          pkgs.coreutils
        ];
      }
      ''
        cp -r ${mkcertCAHelper} $out
        chmod -R +w $out
        patchShebangs $out/bin/
        $out/bin/mkcert-ca-helper $out
      '';
in
{
  options = {
    services.local-networking = {
      baseDomain = lib.mkOption {
        type = lib.types.str;
        default = "lalala.casa";
        example = ''"myhome.network"'';
        description = "The base domain name for services exposed via Traefik (for now).";
      };
      subdomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = ''[ "dashboard" "media" ]'';
        description = "A list of subdomains to configure under the base domain for services and certificates.";
      };
    };
  };

  config = {
    environment.variables = {
      NODE_EXTRA_CA_CERTS = "${mkcertCA}/rootCA.pem";
    };

    # Install CA in system trust store
    security.pki.certificateFiles = [
      "${mkcertCA}/rootCA.pem"
    ];

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    # SOPS secret for Cloudflare API token
    sops.secrets."cloudflare/main/lalala_casa/api_token" = {
      restartUnits = [ "traefik.service" ];
    };

    sops.templates."traefik-cloudflare-env" = {
      content = ''
        CF_DNS_API_TOKEN=${config.sops.placeholder."cloudflare/main/lalala_casa/api_token"}
      '';
      mode = "0400";
      owner = "traefik";
      group = config.services.traefik.group;
    };

    # Ensure traefik data directory and ACME storage exist
    systemd.services.traefik-init = {
      before = [ "traefik.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p ${config.services.traefik.dataDir}
        touch ${config.services.traefik.dataDir}/acme.json
        chmod 600 ${config.services.traefik.dataDir}/acme.json
        chown traefik:${config.services.traefik.group} ${config.services.traefik.dataDir}/acme.json
      '';
    };

    services.traefik = {
      enable = true;
      # make `traefik` user's group "podman" in order access the socket
      group = "podman";

      environmentFiles = [
        config.sops.templates."traefik-cloudflare-env".path
      ];

      staticConfigOptions = {
        # Allow backend services to have self-signed certs
        serversTransport.insecureSkipVerify = true;

        global = {
          checkNewVersion = false;
          sendAnonymousUsage = false;
        };

        # TODO: figure out how to use
        # metrics.prometheus = { };
        # tracing = { };

        entryPoints = {
          web = {
            address = ":80";
            asDefault = true;
            http.redirections.entrypoint = {
              to = "websecure";
              scheme = "https";
            };
          };

          websecure = {
            address = ":443";
            asDefault = true;
            http.tls.certResolver = "cloudflare";
          };
        };

        accessLog = {
          filePath = "${config.services.traefik.dataDir}/access.log";
          format = "json";
        };
        log = {
          level = "INFO";
          filePath = "${config.services.traefik.dataDir}/traefik.log";
          format = "json";
        };

        providers = {
          docker = {
            endpoint = "unix:///var/run/docker.sock";
            # Only expose containers with traefik.enable=true label
            exposedByDefault = false;
          };
          file.watch = true;
        };

        certificatesResolvers.cloudflare = {
          acme = {
            email = "admin@${baseDomain}";
            storage = "${config.services.traefik.dataDir}/acme.json";
            dnsChallenge = {
              provider = "cloudflare";
              resolvers = [
                "1.1.1.1:53"
                "1.0.0.1:53"
              ];
            };
          };
        };

        api.dashboard = true;
        # api.insecure = true;
      };

      dynamicConfigFile = "/etc/traefik/traefik-config.yaml";
    };

    networking.extraHosts = ''
      127.0.0.1 localhost
      ::1       localhost

      # Custom local DNS entries for your services
      ${hostEntries}
    '';

    systemd.tmpfiles.rules = [
      "d ${config.services.traefik.dataDir} 0755 traefik ${config.services.traefik.group} - -"
    ];
  };
}
