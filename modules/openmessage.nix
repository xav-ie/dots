# OpenMessage: Google Messages (SMS/RCS) on nox, as a native app plus an MCP
# server for executor on praesidium.
#
# home-manager installs the app, which spotlight-apps copies to ~/Applications.
# A KeepAlive agent keeps that copy open so its backend (127.0.0.1:7007,
# patched to serve MCP at /mcp) is always up. It goes through `open -W`, so a
# launch from Spotlight or login restore attaches to the running app instead
# of starting a second one, and the agent exits (and relaunches) when the app
# quits. The agent loads before home-manager makes the copy and launchd never
# retries a missing program, so /bin/sh waits for the copy first.
#
# The backend rejects non-loopback Host headers, so openmessage-mcp is an nginx
# that forwards only /mcp with the Host rewritten, on the tailnet address only
# (no auth, like dayflow-mcp). It holds no MCP session of its own, so a backend
# restart is invisible to it; executor adds http://<nox tailnet IP>:<port>/mcp
# as a remote MCP.
_: {
  flake.modules = {
    darwin.macos =
      { config, pkgs, ... }:
      let
        host = "100.100.88.109";
        port = 38991;
        backend = "127.0.0.1:7007";

        nginxConf =
          pkgs.writeText "openmessage-mcp-nginx.conf" # nginx
            ''
              worker_processes 1;
              error_log stderr;
              pid /tmp/openmessage-mcp-nginx.pid;

              events {}

              http {
                access_log off;
                client_body_temp_path /tmp/openmessage-mcp-nginx-body;
                fastcgi_temp_path /tmp/openmessage-mcp-nginx-fastcgi;
                proxy_temp_path /tmp/openmessage-mcp-nginx-proxy;
                scgi_temp_path /tmp/openmessage-mcp-nginx-scgi;
                uwsgi_temp_path /tmp/openmessage-mcp-nginx-uwsgi;

                server {
                  listen ${host}:${toString port};

                  location = /mcp {
                    proxy_pass http://${backend};
                    proxy_set_header Host ${backend};
                    proxy_set_header Origin "";
                    proxy_set_header Referer "";
                    proxy_http_version 1.1;
                    proxy_set_header Connection "";
                    # Streamable HTTP answers can be SSE streams.
                    proxy_buffering off;
                    proxy_read_timeout 1h;
                  }

                  location / {
                    return 404;
                  }
                }
              }
            '';
      in
      {
        # Contacts: names and photos for the people you text. The bundle is
        # ad-hoc signed, so pin its cdhash (re-pinned on every rebuild); the
        # ~/Applications copy keeps the same seal.
        security.tcc.apps = [
          {
            bundleId = "com.openmessage.app";
            appPath = "${pkgs.pkgs-mine.openmessage}/Applications/OpenMessage.app";
            pin = "cdhash";
            services = [ "AddressBook" ];
          }
        ];

        launchd.user.agents = {
          openmessage.serviceConfig = {
            ProgramArguments = [
              "/bin/sh"
              "-c"
              ''until [ -d "$0" ]; do sleep 2; done; exec /usr/bin/open -W "$0"''
              "/Users/${config.system.primaryUser}/Applications/OpenMessage.app"
            ];
            RunAtLoad = true;
            KeepAlive = true;
            ProcessType = "Interactive";
            StandardOutPath = "/tmp/openmessage.out.log";
            StandardErrorPath = "/tmp/openmessage.err.log";
          };
          # KeepAlive retries the bind until tailscaled is up.
          openmessage-mcp.serviceConfig = {
            ProgramArguments = [
              "${pkgs.nginx}/bin/nginx"
              "-e"
              "stderr"
              "-c"
              "${nginxConf}"
              "-g"
              "daemon off;"
            ];
            RunAtLoad = true;
            KeepAlive = true;
            ThrottleInterval = 30;
            StandardOutPath = "/tmp/openmessage-mcp.out.log";
            StandardErrorPath = "/tmp/openmessage-mcp.err.log";
          };
        };
      };

    homeManager.darwin =
      { pkgs, ... }:
      {
        home.packages = [ pkgs.pkgs-mine.openmessage ];
      };
  };
}
