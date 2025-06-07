{
  config,
  lib,
  pkgs,
  ...
}:
let
  domain = "lalala.casa";
  inherit (config.services.local-networking) subdomains;
  allDomains = [
    domain
  ] ++ map (subdomain: "${subdomain}.${domain}") subdomains;
  sanString = lib.concatStringsSep "," (map (d: "DNS:${d}") allDomains);
  hostEntries = lib.concatStringsSep "\n" (
    map (d: ''
      127.0.0.1 ${d}
      ::1       ${d}
    '') allDomains
  );
in
{
  options = {
    services.local-networking = {
      baseDomain = lib.mkOption {
        type = lib.types.str;
        default = domain;
        example = "myhome.network";
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
    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    services.traefik = {
      enable = true;
      # make `traefik` user's group "podman" in order access the socket
      group = "podman";

      staticConfigOptions = {
        # Allow backend services to have self-signed certs
        serversTransport.insecureSkipVerify = true;

        global = {
          checkNewVersion = false;
          sendAnonymousUsage = false;
        };

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
            http.tls = {
              # TODO: replace with cloudflare dns-01
              # using local ca for now
            };
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
        };

        api.dashboard = true;
      };

      dynamicConfigOptions = {
        # https://doc.traefik.io/traefik/https/tls/
        tls.certificates =
          let
            certDir = pkgs.runCommand "selfSignedCerts" { buildInputs = [ pkgs.openssl ]; } ''
              openssl req -x509 \
              -newkey rsa:4096 \
              -keyout key.pem \
              -out cert.pem \
              -nodes \
              -days 3650 \
              -subj "/C=US/ST=Massachusetts/L=Boston/O=Xorlop/OU=Primary/CN=${domain}" \
              -addext "subjectAltName = ${sanString}"
              mkdir -p $out
              cp key.pem cert.pem $out
            '';
          in
          [
            {
              certFile = "${certDir}/cert.pem";
              keyFile = "${certDir}/key.pem";
            }
          ];
      };
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
