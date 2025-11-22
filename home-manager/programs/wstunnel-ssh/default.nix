# SSH over WebSocket client configuration
# Provides wstunnel package and SSH config for accessing praesidium through hostile networks
{ pkgs, ... }:
{
  config = {
    home.packages = [ pkgs.wstunnel ];

    programs.ssh.matchBlocks = {
      # SSH over WebSocket for accessing praesidium through hostile networks
      "praesidium-ws" = {
        hostname = "127.0.0.1";
        # Use wstunnel client to connect through WebSocket on port 443
        # The tunnel connects to ssh.lalala.casa and forwards to SSH on the remote end
        proxyCommand = "wstunnel client --log-lvl=off -L stdio://127.0.0.1:22 wss://ssh.lalala.casa";
        user = "x";
        identityFile = "~/.ssh/id_ed25519";
      };
    };
  };
}
