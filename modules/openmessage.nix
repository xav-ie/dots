# OpenMessage: Google Messages (SMS/RCS) and Signal on nox, as a native app
# plus an MCP server for executor on praesidium.
#
# home-manager installs the app, which spotlight-apps copies to ~/Applications.
# openmessage-backend keeps the copy's own backend binary serving (web UI and
# MCP at 127.0.0.1:7007/mcp) whether or not the window is open; when
# spotlight-apps re-copies the app, the home-manager activation restarts the
# agent onto the new binary (launchd's WatchPaths can't do this: it watches
# the bundle's original inode, which rm-rf-plus-ditto replaces). The app only
# adopts a backend started from its own binary path, and is patched never to
# start one itself (serve takes no instance lock, and a second backend would
# run a second signal-cli on the account). openmessage opens the app once at
# login; quitting it leaves the backend up. Both wait for the ~/Applications
# copy, which home-manager makes after the agents load (launchd never retries
# a missing program).
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
        home = "/Users/${config.system.primaryUser}";
        app = "${home}/Applications/OpenMessage.app";

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
          # The environment the app's own launcher gives its backend, plus the
          # MCP transport, the jitfix-wrapped signal-cli and the v2 store
          # (migrated with `openmessage migrate`), where upstream pairs
          # sent-message echoes; the legacy store shows every send twice.
          openmessage-backend.serviceConfig = {
            ProgramArguments = [
              "/bin/sh"
              "-c"
              ''until [ -x "$0" ]; do sleep 2; done; exec "$0" serve --web --mcp-sse''
              "${app}/Contents/Resources/openmessage"
            ];
            EnvironmentVariables = {
              HOME = home;
              OPENMESSAGES_APP_SANDBOX = "1";
              OPENMESSAGES_DATA_DIR = "${home}/Library/Application Support/OpenMessage";
              OPENMESSAGES_LOG_LEVEL = "info";
              OPENMESSAGES_MACOS_NOTIFICATIONS = "0";
              OPENMESSAGES_PORT = "7007";
              OPENMESSAGES_SIGNAL_CLI = "${pkgs.pkgs-mine.openmessage.signal-cli}";
              OPENMESSAGES_V2_PRIMARY = "1";
              PATH = "/usr/bin:/bin";
            };
            WorkingDirectory = "${home}/Library/Application Support/OpenMessage";
            RunAtLoad = true;
            KeepAlive = true;
            ProcessType = "Background";
            StandardOutPath = "/tmp/openmessage-backend.out.log";
            StandardErrorPath = "/tmp/openmessage-backend.err.log";
          };
          openmessage.serviceConfig = {
            ProgramArguments = [
              "/bin/sh"
              "-c"
              ''until [ -d "$0" ]; do sleep 2; done; exec /usr/bin/open -g "$0"''
              app
            ];
            RunAtLoad = true;
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
      { pkgs, lib, ... }:
      let
        # spotlight-apps re-copies ~/Applications/OpenMessage.app only when its
        # store path changes, and the backend agent's plist is identical before
        # and after, so nothing else restarts it: the running process would
        # keep serving the old embedded web UI until this kicks it onto the
        # new binary. Guarded by the spotlight-apps marker, so an unchanged
        # app never restarts the backend.
        restart-backend = pkgs.writeShellApplication {
          name = "openmessage-restart-backend";
          runtimeInputs = [ pkgs.coreutils ];
          text = # sh
            ''
              marker="''${HOME}/.local/state/hm-spotlight-apps/OpenMessage.app.source"
              state="''${HOME}/.local/state/openmessage-backend.source"
              [ -r "$marker" ] || exit 0
              if [ "$(cat "$state" 2>/dev/null)" = "$(cat "$marker")" ]; then exit 0; fi
              echo "openmessage: app re-copied; restarting the backend"
              /bin/launchctl kickstart -k "gui/$(id -u)/org.nixos.openmessage-backend"
              mkdir -p "$(dirname "$state")"
              cat "$marker" > "$state"
            '';
        };
      in
      {
        home.packages = [ pkgs.pkgs-mine.openmessage ];
        home.activation.openmessageBackendRestart =
          lib.hm.dag.entryAfter [ "spotlightApps" ] "${restart-backend}/bin/openmessage-restart-backend";
      };
  };
}
