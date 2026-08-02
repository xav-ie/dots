{
  flake.modules.nixos.praesidium =
    { pkgs, ... }:
    let
      inherit (pkgs.pkgs-mine) protonmail-mcp;
      # Bridge presents a self-signed cert with CN=127.0.0.1, but we dial the bridge
      # container by name. SMTP already forces rejectUnauthorized:false, but IMAP only
      # relaxes it when the host string is literally localhost/127.0.0.1. So drop cert
      # validation for this one process — an env var in the shared proxy env would
      # leak to every other Node MCP. The hop is a private podman network reachable by
      # nothing but this container, so there's nothing to MITM.
      wrapped = pkgs.writeShellScript "protonmail-mcp-wrapped" ''
        export NODE_TLS_REJECT_UNAUTHORIZED=0

        # Refuse to start if the bridge is unreachable; protonmail-mcp would
        # otherwise advertise tools that fail at call time. mcp-resilient only
        # degrades a backend to an empty tool list on a NON-ZERO exit. Backends
        # spawn per request, so this re-probes and recovers on its own.
        if ! ${pkgs.coreutils}/bin/timeout 3 ${pkgs.bash}/bin/bash -c \
          ": < /dev/tcp/$PROTONMAIL_IMAP_HOST/$PROTONMAIL_IMAP_PORT" 2>/dev/null; then
          echo "protonmail-mcp: bridge $PROTONMAIL_IMAP_HOST:$PROTONMAIL_IMAP_PORT unreachable" >&2
          exit 1
        fi

        exec ${protonmail-mcp}/bin/protonmail-mcp-server "$@"
      '';
    in
    {
      services.mcp-proxy.servers.protonmail = {
        command = "${wrapped}";
        packages = [ protonmail-mcp ];
        secretEnvVars = {
          PROTONMAIL_USERNAME = "proton/smtp_username";
          PROTONMAIL_PASSWORD = "proton/smtp_password";
        };
        envVars = {
          # 2025/2143 are the bridge container's relay ports (socat), not Bridge's own
          # 1025/1143 loopback listeners — see modules/protonmail-bridge.nix.
          PROTONMAIL_SMTP_HOST = "protonmail-bridge";
          PROTONMAIL_SMTP_PORT = "2025";
          PROTONMAIL_IMAP_HOST = "protonmail-bridge";
          PROTONMAIL_IMAP_PORT = "2143";
        };
      };
    };
}
