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

        # Refuse to start if the bridge is unreachable. Left alone,
        # protonmail-mcp starts anyway, logs "email features will be limited",
        # and still advertises send/read tools that fail at call time — an
        # agent sees a healthy source and discovers the breakage mid-task.
        #
        # mcp-resilient only degrades a backend to an empty tool list when it
        # exits NON-ZERO, so exiting here is what converts a lying source into
        # an honestly absent one. Backends are spawned per request, so this is
        # re-probed on every spawn and recovers by itself once the bridge is
        # back — no restart needed.
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
