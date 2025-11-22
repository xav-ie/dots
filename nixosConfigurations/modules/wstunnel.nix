# SSH over WebSocket for accessing SSH through hostile networks that block port 22
#
# Usage (client):
#   ssh praesidium-ws    # uses ProxyCommand configured in home-manager/programs/ssh
#
# Architecture:
#   client → wss://ssh.lalala.casa:443 → Traefik → wstunnel:8080 → SSH:22
#
# Testing (server):
#   systemctl status wstunnel-ssh-server
#   journalctl -u wstunnel-ssh-server -f
#
# Testing (client):
#   wstunnel client -L tcp://127.0.0.1:2222://127.0.0.1:22 wss://ssh.lalala.casa
#   ssh -p 2222 user@localhost

{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.wstunnel-ssh;
in
{
  options.services.wstunnel-ssh = {
    enable = mkEnableOption "wstunnel SSH-over-WebSocket server";

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Local port for wstunnel server to listen on";
    };

    sshHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "SSH server host to forward connections to";
    };

    sshPort = mkOption {
      type = types.port;
      default = 22;
      description = "SSH server port to forward connections to";
    };
  };

  config = mkIf cfg.enable {
    # Register subdomain with local networking
    services.local-networking.subdomains = [ "ssh" ];

    # Install wstunnel package
    environment.systemPackages = [ pkgs.wstunnel ];

    # Create systemd service for wstunnel server
    systemd.services.wstunnel-ssh-server = {
      description = "wstunnel server for SSH over WebSocket";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        User = "wstunnel";
        Group = "wstunnel";

        # Security hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        # Start wstunnel server
        # Using ws:// locally since Traefik handles TLS termination
        # --restrict-to ensures only SSH traffic is allowed
        ExecStart = "${pkgs.wstunnel}/bin/wstunnel server ws://127.0.0.1:${toString cfg.port} --restrict-to ${cfg.sshHost}:${toString cfg.sshPort}";

        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
