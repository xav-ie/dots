{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.reverse-proxy;
  inherit (config.services.local-networking) baseDomain;
  cfgSecret = config.sops.placeholder;
in
{
  options = {
    services.reverse-proxy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        example = "true";
        description = "Whether to enable the reverse proxy.";
      };

      # TODO: make an array of proxies instead of just one
      name = lib.mkOption {
        type = lib.types.str;
        default = "my-local-proxy";
        example = ''"my-local-proxy"'';
        description = ''
          The name for the reverse-proxy, so traefik may create a service
          config.
        '';
      };
    };
  };

  config = {
    environment.etc."traefik/my-traefik-config.yaml".source =
      config.sops.templates."reverse-proxy/my-traefik-config.yaml".path;

    sops = {
      secrets =
        let
          secretConfig.restartUnits = lib.optional cfg.enable "nginx.service";
        in
        {
          "reverse-proxy/dev-hostname" = secretConfig;
          "reverse-proxy/shopify-hostname" = secretConfig;
          "reverse-proxy/reverse-hostname" = secretConfig;
          "reverse-proxy/extra-cookie-domain" = secretConfig;
        };

      templates = {
        "reverse-proxy/my-traefik-config.yaml" = {
          content = lib.generators.toYAML { } {
            tls = {
              certificates = [
                {
                  certFile = "/var/lib/traefik/certs/cert.pem";
                  keyFile = "/var/lib/traefik/certs/key.pem";
                }
              ];
            };
            http = {
              routers = {
                ${cfg.name} = {
                  rule = "Host(`${cfgSecret."reverse-proxy/reverse-hostname"}`)";
                  service = "${cfg.name}-service";
                  tls = true;
                };
                dashboard = {
                  rule = "Host(`${baseDomain}`)";
                  service = "api@internal";
                  tls = true;
                };
              };
              services.${cfg.name + "-service"} = {
                loadBalancer = {
                  servers = [
                    { url = "http://127.0.0.1:8081"; }
                  ];
                };
              };
            };
          };
          mode = "0444";
        };

        "reverse-proxy/cookie-domain-rewrite" = {
          content = # nginx
            ''
              proxy_cookie_domain ${cfgSecret."reverse-proxy/dev-hostname"} ${
                cfgSecret."reverse-proxy/reverse-hostname"
              };
              proxy_cookie_domain ${cfgSecret."reverse-proxy/extra-cookie-domain"} ${
                cfgSecret."reverse-proxy/reverse-hostname"
              };
            '';
          mode = "0444";
        };

        "reverse-proxy/domain-variables" = {
          content = # nginx
            ''
              set $dev_hostname "${cfgSecret."reverse-proxy/dev-hostname"}";
              set $shopify_hostname "${cfgSecret."reverse-proxy/shopify-hostname"}";
              set $reverse_hostname "${cfgSecret."reverse-proxy/reverse-hostname"}";
            '';
          mode = "0444";
        };

        "reverse-proxy/dnsmasq-conf" = {
          content = "";
          # content = ''
          #   host-record=${cfgSecret."reverse-proxy/reverse-hostname"},127.0.0.1,::1
          # '';
          path = "/etc/dnsmasq.d/reverse-proxy.conf";
          mode = "0444";
          restartUnits = [ "dnsmasq.service" ];
        };
      };
    };

    services.nginx = {
      inherit (cfg) enable;

      # Worker configuration
      appendConfig = # nginx
        ''
          worker_processes auto;
          worker_rlimit_nofile 8192;
        '';

      # Events configuration
      eventsConfig = # nginx
        ''
          worker_connections 4096;
          use epoll;
          multi_accept on;
        '';

      recommendedTlsSettings = true;
      recommendedOptimisation = false;
      recommendedGzipSettings = true;
      recommendedProxySettings = false;

      additionalModules = with pkgs.nginxModules; [ moreheaders ];

      appendHttpConfig = # nginx
        ''
          sendfile on;
          # TCP optimizations
          tcp_nodelay on;
          tcp_nopush on;

          # DNS caching with IPv4 only
          resolver 8.8.8.8 1.1.1.1 valid=300s ipv6=off;
          resolver_timeout 10s;

          # Proxy optimizations
          proxy_buffering on;
          proxy_request_buffering on;
          proxy_buffer_size 8k;
          proxy_buffers 16 8k;
          proxy_busy_buffers_size 16k;
          proxy_temp_file_write_size 64k;
          proxy_headers_hash_max_size 2048;
          proxy_headers_hash_bucket_size 256;

          # Global keepalive settings
          keepalive_requests 1000;
          keepalive_timeout 65;

          # Enable useful features
          proxy_intercept_errors on;
          proxy_ignore_client_abort on;

          # Rate limiting to prevent overload
          limit_req_zone $binary_remote_addr zone=api:10m rate=100r/s;
          limit_req_zone $binary_remote_addr zone=static:10m rate=200r/s;

          include "${config.sops.templates."reverse-proxy/cookie-domain-rewrite".path}";
        '';

      virtualHosts.${cfg.name} = {
        listen =
          let
            port = 8081;
          in
          [
            {
              addr = "127.0.0.1";
              inherit port;
            }
            {
              addr = "[::1]";
              inherit port;
            }
          ];

        extraConfig = # nginx
          ''
            include "${config.sops.templates."reverse-proxy/domain-variables".path}";
          '';

        locations =
          let
            goToShopify = {
              # Use the NGINX variable for the proxy pass.
              proxyPass = "https://$shopify_hostname";
              proxyWebsockets = false;

              extraConfig = # nginx
                ''
                  # Rate limiting for Shopify requests
                  limit_req zone=static burst=50 nodelay;

                  # Use NGINX variables for headers.
                  proxy_set_header Host $reverse_hostname;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_set_header X-Forwarded-Host $host;

                  # SSL settings
                  proxy_ssl_verify off;
                  proxy_ssl_server_name on;
                  proxy_ssl_name $reverse_hostname;

                  # Timeouts
                  proxy_connect_timeout 20s;
                  proxy_send_timeout 60s;
                  proxy_read_timeout 120s;

                  # Standard HTTP/1.1 with keepalive
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";

                  # Buffering for better performance
                  proxy_buffering on;
                  proxy_buffer_size 8k;
                  proxy_buffers 8 8k;

                  proxy_cookie_path / "/; secure; SameSite=Lax";
                '';
            };
            respond204 = {
              return = "204";
              extraConfig = # nginx
                ''
                  add_header Cache-Control "no-cache, no-store, must-revalidate";
                  add_header Access-Control-Allow-Origin "*";
                  add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
                '';
            };
          in
          {
            # Fast responses for problematic endpoints
            "~ ^/__analytics__" = respond204;

            # Shopify routes
            "~ ^/pages/outsmartly" = goToShopify;
            "~ ^/cdn/" = goToShopify;
            "~ ^/products/*\.js$" = goToShopify;
            "~ ^/contact" = goToShopify;

            # Main proxy with optimizations
            "/" = {
              # Use the NGINX variable for the proxy pass.
              proxyPass = "https://$dev_hostname";
              proxyWebsockets = false;

              extraConfig = # nginx
                ''
                  # Rate limiting for main site
                  limit_req zone=api burst=100 nodelay;

                  # Use NGINX variables for headers and redirects.
                  proxy_set_header Host $dev_hostname;
                  proxy_set_header X-Real-IP $remote_addr;
                  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  proxy_set_header X-Forwarded-Proto $scheme;
                  proxy_set_header X-Forwarded-Host $host;

                  # SSL settings
                  proxy_ssl_verify off;
                  proxy_ssl_server_name on;

                  # Timeouts
                  proxy_connect_timeout 30s;
                  proxy_send_timeout 120s;
                  proxy_read_timeout 300s;

                  # Standard HTTP/1.1 with keepalive
                  proxy_http_version 1.1;
                  proxy_set_header Connection "";

                  # Enable buffering for better performance
                  proxy_buffering on;
                  proxy_buffer_size 8k;
                  proxy_buffers 16 8k;
                  proxy_busy_buffers_size 16k;

                  # Error handling with retries
                  proxy_next_upstream error timeout http_502 http_503 http_504;
                  proxy_next_upstream_tries 2;
                  proxy_next_upstream_timeout 30s;

                  proxy_redirect https://$dev_hostname/ https://$reverse_hostname/;

                  proxy_cookie_path / "/; secure; SameSite=Lax";
                '';
            };
          };
      };
    };
  };
}
