{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.services.local-networking) baseDomain subdomains;

      # --- Traefik dynamic configuration -------------------------------------
      #
      # Moved here from nginx.nix, which owned an nginx *and* Traefik's routing
      # table. Keeping them apart is not cosmetic: a `//` applied one level too
      # high there replaced the whole `services` map instead of adding to it,
      # taking six unrelated backends offline while every router still resolved
      # and the config stayed valid.

      # Shared between the router that references it and the spec that defines it.
      chromeLocalhostHost = "chrome-localhost-host";
      snippetsStripPrefix = "snippets-strip-prefix";

      # Each proxied service is a router and a service that agree by string.
      # Generating the pair from one spec removes the agreement problem; the
      # specs themselves come from the modules that own the daemons, via
      # `services.local-networking.proxies`.
      mkProxy = name: p: {
        routers.${name} = {
          rule = if p.rule == null then "Host(`${p.subdomain}.${baseDomain}`)" else p.rule;
          service = "${name}-service";
          tls.certResolver = "cloudflare";
        }
        // lib.optionalAttrs (p.middlewares != [ ]) { inherit (p) middlewares; }
        // lib.optionalAttrs (p.priority != null) { inherit (p) priority; };
        services."${name}-service" = lib.recursiveUpdate {
          loadBalancer.servers = [ { url = "http://127.0.0.1:${toString p.port}"; } ];
        } p.service;
      };

      proxied =
        config.services.local-networking.proxies
        |> lib.mapAttrsToList mkProxy
        |> lib.foldl' lib.recursiveUpdate {
          routers = { };
          services = { };
        };

      traefikDynamic = {
        http = {
          routers = proxied.routers // {
            dashboard = {
              rule = "Host(`${baseDomain}`) || Host(`traefik.${baseDomain}`)";
              # Traefik's own dashboard, served by the API — it has no entry in
              # `services` and never will.
              service = "api@internal";
              tls.certResolver = "cloudflare";
            };
          };
          inherit (proxied) services;
          middlewares = {
            ${chromeLocalhostHost}.headers.customRequestHeaders.Host = "localhost";
            ${snippetsStripPrefix}.stripPrefix.prefixes = [ "/snippets" ];
          };
        };
      };

      # Every router names a service, and nothing in Traefik's schema requires
      # that service to exist — a dangling reference is valid config that fails
      # at request time. Checking it here turns a silent 502 into a build error
      # that names the routers.
      #
      # A name containing `@` belongs to another provider (`api@internal`, or a
      # container published by the docker provider) and is unknowable from this
      # file, so it is not ours to check. Excluding only `api@internal` would
      # fail the build the first time a file router pointed at a container.
      danglingRouters = lib.filterAttrs (
        _: r: !(lib.hasInfix "@" r.service) && !(traefikDynamic.http.services ? ${r.service})
      ) traefikDynamic.http.routers;

      # A proxy already knows its own subdomain, so it does not have to be
      # listed twice. `subdomains` stays for the hosts that Traefik routes some
      # other way — the container labels the docker provider reads — which need
      # a certificate and a hosts entry but have no entry here.
      proxySubdomains =
        config.services.local-networking.proxies |> lib.mapAttrsToList (_: p: p.subdomain);

      allDomains = [
        baseDomain
      ]
      ++ (subdomains ++ proxySubdomains |> lib.unique |> map (s: "${s}.${baseDomain}"));
      hostEntries =
        allDomains
        |> map (d: ''
          127.0.0.1 ${d}
          ::1       ${d}
        '')
        |> lib.concatStringsSep "\n";
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
          } # sh
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
          proxies = lib.mkOption {
            default = { };
            description = ''
              Services to expose through Traefik, contributed by the module that
              owns each one.

              Declared here and set there on purpose: a router and its service
              agree only by string, and the port belongs next to the daemon that
              listens on it. Because this is an attrset option the module system
              merges the contributions — nothing hand-merges attrsets, which is
              what once replaced the whole services map instead of adding to it.
            '';
            example = lib.literalExpression ''{ muscat = { subdomain = "muscat"; port = 8763; }; }'';
            type = lib.types.attrsOf (
              lib.types.submodule (
                { name, ... }:
                {
                  options = {
                    subdomain = lib.mkOption {
                      type = lib.types.str;
                      default = name;
                      description = "Host is <subdomain>.<baseDomain>, unless `rule` overrides it.";
                    };
                    rule = lib.mkOption {
                      type = lib.types.nullOr lib.types.str;
                      default = null;
                      description = "A full Traefik rule, for anything that is not a plain host match.";
                    };
                    port = lib.mkOption {
                      type = lib.types.port;
                      description = "Loopback port the service listens on.";
                    };
                    priority = lib.mkOption {
                      type = lib.types.nullOr lib.types.int;
                      default = null;
                      description = "Router priority, where two rules can both match.";
                    };
                    middlewares = lib.mkOption {
                      type = lib.types.listOf lib.types.str;
                      default = [ ];
                      description = "Middleware names to apply to the router.";
                    };
                    service = lib.mkOption {
                      type = lib.types.attrs;
                      default = { };
                      description = "Extra loadBalancer settings, merged over the generated one.";
                    };
                  };
                }
              )
            );
          };
          caCertFile = lib.mkOption {
            type = lib.types.path;
            default = "${mkcertCA}/rootCA.pem";
            readOnly = true;
            description = "Path to the local mkcert CA certificate (for containers needing to trust *.lalala.casa TLS).";
          };
        };
      };

      config = {
        # An `assert` in the module body would be evaluated during the module
        # fixpoint, before `config` exists — and these routers read config, so
        # that is an infinite recursion. `assertions` is the mechanism that runs
        # after evaluation settles.
        assertions = [
          {
            assertion = danglingRouters == { };
            message = "traefik routers point at services that do not exist: ${lib.concatStringsSep ", " (lib.attrNames danglingRouters)}";
          }
        ];

        environment.etc."traefik/traefik-config.yaml".source =
          config.sops.templates."traefik-config.yaml".path;

        sops.templates."traefik-config.yaml" = {
          content = lib.generators.toYAML { } traefikDynamic;
          mode = "0444";
          restartUnits = [ "traefik.service" ];
        };

        services.local-networking.subdomains = [ "traefik" ];

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
          inherit (config.services.traefik) group;
        };

        # Ensure traefik data directory and ACME storage exist
        systemd.services.traefik-init = {
          before = [ "traefik.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = # sh
            ''
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

        networking.extraHosts = # ini
          ''
            127.0.0.1 localhost
            ::1       localhost

            # Custom local DNS entries for your services
            ${hostEntries}
          '';

      };
    };
}
