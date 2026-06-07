{
  flake.modules.nixos.linux =
    { pkgs, ... }:
    {
      # A readiness target for "the system resolver actually answers queries",
      # not just "a DNS unit was started". Use this instead of After=<provider>
      # so dependents survive swapping the DNS server (dnsmasq → resolved → ...).
      #
      # Layered on top of nss-lookup.target: that target indicates the DNS
      # provider has reached its "active" state (e.g. dnsmasq's DBus name was
      # claimed), which can race the actual socket bind. The probe below
      # connects to [::1]:53 / 127.0.0.1:53 and only declares the target
      # reached once one accepts.
      systemd.targets.dns-online = {
        description = "DNS resolver is responsive";
        wantedBy = [ "multi-user.target" ];
      };

      systemd.services.dns-online-probe = {
        description = "Wait for the system DNS resolver to answer queries";
        after = [ "nss-lookup.target" ];
        wants = [ "nss-lookup.target" ];
        before = [ "dns-online.target" ];
        requiredBy = [ "dns-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "15s";
        };

        script = # sh
          ''
            bash=${pkgs.bash}/bin/bash
            # Require *both* loopback addresses to answer, not either. dnsmasq
            # with `bind-dynamic` binds IPv4 before IPv6, so accepting just
            # 127.0.0.1 lets IPv6-preferring clients (cloudflared, glibc with
            # AAAA preference) start before [::1]:53 is bound and time out on
            # their first query.
            for _ in $(seq 1 100); do
              if timeout 0.2 "$bash" -c ": </dev/tcp/[::1]/53" 2>/dev/null \
                 && timeout 0.2 "$bash" -c ": </dev/tcp/127.0.0.1/53" 2>/dev/null; then
                exit 0
              fi
              sleep 0.1
            done
            # Don't fail boot if DNS is genuinely broken — let dependents see
            # the resolver error themselves rather than blocking the unit graph.
            exit 0
          '';
      };
    };
}
