{ pkgs, ... }:
{
  # too slow :(
  # TODO: use a different dns server
  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    resolveLocalQueries = true;
    settings = {
      dnssec = false;
      # set trust anchors?
      conf-file = "${pkgs.dnsmasq.outPath}/share/dnsmasq/trust-anchors.conf";
      # Never forward plain names (without a dot or domain part)
      domain-needed = true;
      # allow dynamic config files, useful for sensitive information
      conf-dir = "/etc/dnsmasq.d/,*.conf";
      # go to our DOH resolver
      # server = [ "127.0.0.1#5053" ];
      # allow more concurrent DNS requests
      dns-forward-max = 2000;
      all-servers = true; # Query all servers, use fastest response
      no-poll = true; # Don't poll for upstream changes

      # listen-address alone is enough to keep dnsmasq off the wildcard
      # (and out of aardvark-dns's container interfaces) per dnsmasq's
      # own docs: "If no --interface or --listen-address options are
      # given dnsmasq listens on all available interfaces." Restricting
      # to lo's IPs means local apps (which query 127.0.0.1 / ::1 from
      # /etc/resolv.conf) work, and there's no `interface tailscale0
      # does not currently exist` warning on boot.
      bind-dynamic = true;
      listen-address = [
        "127.0.0.1"
        "::1"
      ];

      cache-size = 10000;
      min-cache-ttl = 300;
      max-cache-ttl = 3600;

      dnssec-check-unsigned = false;

      # Send only Tailscale domains to Tailscale MagicDNS
      # All other queries go directly to Cloudflare (1.1.1.1)
      server = [
        "/ts.net/100.100.100.100" # Only .ts.net domains to Tailscale
        "2606:4700:4700::1111" # Cloudflare DNS (IPv6)
        "1.1.1.1" # Cloudflare DNS (IPv4)
        "2606:4700:4700::1001" # Cloudflare DNS (IPv6 backup)
        "1.0.0.1" # Cloudflare DNS (IPv4 backup)
      ];
    };
  };

  # services.dnscrypt-proxy2 = {
  #   enable = true;
  #   settings = {
  #     ipv6_servers = true;
  #     require_dnssec = true;
  #     require_nolog = true;
  #     require_nofilter = true;
  #
  #     sources.public-resolvers = {
  #       urls = [
  #         "https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md"
  #         "https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md"
  #       ];
  #       cache_file = "/var/lib/dnscrypt-proxy/public-resolvers.md";
  #       minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
  #     };
  #
  #     server_names = [
  #       "cloudflare"
  #       "cloudflare-ipv6"
  #     ];
  #   };
  # };
}
