{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      server = pkgs.writers.writePython3Bin "agent-mcp-server" {
        libraries = [ pkgs.python3Packages.mcp ];
        flakeIgnore = [ "E501" ];
      } (builtins.readFile ./server.py);
      # envVars are container-wide (merged across servers), so claude's PATH
      # and settings are set in a wrapper instead.
      launcher = pkgs.writeShellScriptBin "agent-mcp" ''
        export PATH=${pkgs.claude-code}/bin:$PATH
        export DISABLE_AUTOUPDATER=1
        export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
        exec ${server}/bin/agent-mcp-server "$@"
      '';
    in
    {
      sops.secrets."claude/oauth_token" = { };

      services.mcp-proxy.servers.agent = {
        command = "${launcher}/bin/agent-mcp";
        packages = [ launcher ];
        # Long-lived subscription token from `claude setup-token`.
        secretEnvVars = {
          CLAUDE_CODE_OAUTH_TOKEN = "claude/oauth_token";
        };
      };
    };
}
