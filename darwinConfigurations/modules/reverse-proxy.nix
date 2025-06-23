{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.reverse-proxy;
  cfgSecret = config.sops.placeholder;

  nginxConf =
    let
      goToShopify = # nginx
        ''
          limit_req zone=static burst=50 nodelay;

          proxy_pass https://$shopify_hostname;
          proxy_set_header Host $reverse_hostname;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;

          proxy_ssl_verify off;
          proxy_ssl_server_name on;
          proxy_ssl_name $reverse_hostname;

          proxy_connect_timeout 20s;
          proxy_send_timeout 60s;
          proxy_read_timeout 120s;

          proxy_http_version 1.1;
          proxy_set_header Connection "";

          proxy_buffering on;
          proxy_buffer_size 8k;
          proxy_buffers 8 8k;
        '';
    in
    pkgs.writeText "nginx.conf" # nginx
      ''
        worker_processes auto;
        worker_rlimit_nofile 8192;
        error_log /var/log/nginx/error.log;
        pid /var/run/nginx.pid;

        events {
          worker_connections 4096;
          use kqueue;
          multi_accept on;
        }

        http {
          include ${pkgs.nginx}/conf/mime.types;
          default_type application/octet-stream;

          sendfile on;
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

          # TLS settings
          ssl_protocols TLSv1.2 TLSv1.3;
          ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
          ssl_prefer_server_ciphers off;

          # Gzip
          gzip on;
          gzip_vary on;
          gzip_proxied any;
          gzip_comp_level 5;
          gzip_types text/plain text/css text/xml application/json application/javascript application/rss+xml application/atom+xml image/svg+xml;

          # cookie domain fixes
          include "${config.sops.templates."reverse-proxy/cookie-domain-rewrite".path}";

          server {
            listen 443 ssl;
            listen [::]:443 ssl;

            ssl_certificate /var/lib/certs/cert.pem;
            ssl_certificate_key /var/lib/certs/key.pem;

            # Domain variables
            include "${config.sops.templates."reverse-proxy/domain-variables".path}";

            server_name $reverse_hostname;

            # Fast responses for problematic endpoints
            location ~ ^/__analytics__ {
              return 204;
              add_header Cache-Control "no-cache, no-store, must-revalidate";
              add_header Access-Control-Allow-Origin "*";
              add_header Access-Control-Allow-Methods "GET, POST, OPTIONS";
            }

            # Shopify routes
            location ~ ^/(cdn|cart|pages/outsmartly) {
              ${goToShopify}
            }

            # Main proxy with optimizations
            location / {
              limit_req zone=api burst=100 nodelay;

              proxy_pass https://$dev_hostname;
              proxy_set_header Host $dev_hostname;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header X-Forwarded-Host $host;

              proxy_ssl_verify off;
              proxy_ssl_server_name on;

              proxy_connect_timeout 30s;
              proxy_send_timeout 120s;
              proxy_read_timeout 300s;

              proxy_http_version 1.1;
              proxy_set_header Connection "";

              proxy_buffering on;
              proxy_buffer_size 8k;
              proxy_buffers 16 8k;
              proxy_busy_buffers_size 16k;

              proxy_next_upstream error timeout http_502 http_503 http_504;
              proxy_next_upstream_tries 2;
              proxy_next_upstream_timeout 30s;

              proxy_redirect https://$dev_hostname/ https://$reverse_hostname/;
            }
          }
        }
      '';
in
{
  options.services.reverse-proxy = {
    enable = lib.mkEnableOption "reverse proxy";
  };

  config = lib.mkIf cfg.enable {
    # TODO: refactor and combine with nixos
    sops = {
      secrets = {
        "reverse-proxy/reverse-hostname" = { };

        "reverse-proxy/dev-hostname" = { };
        "reverse-proxy/shopify-hostname" = { };
        "reverse-proxy/extra-cookie-domain" = { };
      };

      templates = {
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
      };
    };

    environment.systemPackages = [ pkgs.nginx ];

    launchd.daemons.nginx = {
      serviceConfig = {
        ProgramArguments = [
          "${pkgs.nginx}/bin/nginx"
          "-c"
          "${nginxConf}"
          "-g"
          "daemon off;"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        StandardErrorPath = "/var/log/nginx/error.log";
        StandardOutPath = "/var/log/nginx/access.log";
      };
    };

    system.activationScripts.preActivation.text = ''
      mkdir -p /var/log/nginx /var/run
      touch /var/log/nginx/error.log /var/log/nginx/access.log
    '';
  };
}
