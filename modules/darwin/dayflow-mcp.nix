# dayflow-mcp: Dayflow's MCP only speaks stdio and only exists on this Mac,
# while executor runs on praesidium. mcp-proxy serves it as streamable HTTP
# (http://<nox tailnet IP>:<port>/mcp) for executor to add as a remote MCP.
# Bound to the tailnet address only, since the timeline is screen-derived and
# the server has no auth. KeepAlive retries the bind until tailscaled is up.
# The CLI goes on PATH as a wrapper instead of via `dayflow link`, which
# writes to /usr/local/bin outside nix.
_: {
  flake.modules.darwin.macos =
    { pkgs, ... }:
    let
      cli = "/Applications/Dayflow.app/Contents/Helpers/dayflow";
      host = "100.100.88.109";
      port = 38990;
    in
    {
      environment.systemPackages = [
        (pkgs.writeShellScriptBin "dayflow" ''exec ${cli} "$@"'')
      ];

      launchd.user.agents.dayflow-mcp.serviceConfig = {
        ProgramArguments = [
          "${pkgs.mcp-proxy}/bin/mcp-proxy"
          "--host"
          host
          "--port"
          (toString port)
          "--stateless"
          cli
          "mcp"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 30;
        StandardOutPath = "/tmp/dayflow-mcp.out.log";
        StandardErrorPath = "/tmp/dayflow-mcp.err.log";
      };
    };
}
