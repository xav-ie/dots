# OpenMessage: Google Messages (SMS/RCS) on nox, as a native app plus an MCP
# server for executor on praesidium.
#
# home-manager installs the app, which spotlight-apps copies to ~/Applications.
# A KeepAlive agent runs the store bundle so its backend (127.0.0.1:7007,
# patched to serve MCP at /mcp) is always up; the agent loads before
# home-manager makes that copy, and launchd never retries a missing program. The backend rejects non-loopback Host
# headers, so openmessage-mcp re-serves it through mcp-proxy as a client, on
# the tailnet address only (no auth, like dayflow-mcp): executor adds
# http://<nox tailnet IP>:<port>/mcp as a remote MCP.
_: {
  flake.modules = {
    darwin.macos =
      { pkgs, ... }:
      let
        host = "100.100.88.109";
        port = 38991;
      in
      {
        launchd.user.agents = {
          openmessage.serviceConfig = {
            ProgramArguments = [
              "${pkgs.pkgs-mine.openmessage}/Applications/OpenMessage.app/Contents/MacOS/OpenMessage"
            ];
            RunAtLoad = true;
            KeepAlive = true;
            ProcessType = "Interactive";
            StandardOutPath = "/tmp/openmessage.out.log";
            StandardErrorPath = "/tmp/openmessage.err.log";
          };
          openmessage-mcp.serviceConfig = {
            ProgramArguments = [
              "${pkgs.mcp-proxy}/bin/mcp-proxy"
              "--host"
              host
              "--port"
              (toString port)
              "--stateless"
              "--"
              "${pkgs.mcp-proxy}/bin/mcp-proxy"
              "--transport"
              "streamablehttp"
              "http://127.0.0.1:7007/mcp"
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
