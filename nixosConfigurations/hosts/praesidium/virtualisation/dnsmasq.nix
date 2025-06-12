{ pkgs, ... }:
{
  services.dnsmasq = {
    enable = true;
    alwaysKeepRunning = true;
    resolveLocalQueries = true;
    settings = {
      dnssec = true;
      # set trust anchors?
      conf-file = "${pkgs.dnsmasq.outPath}/share/dnsmasq/trust-anchors.conf";
      # Never forward plain names (without a dot or domain part)
      domain-needed = true;
      # allow dynamic config files, useful for sensistive information
      conf-dir = "/etc/dnsmasq.d/,*.conf";
      # go to our DOH resolver
      # server = [ "127.0.0.1#5053" ];
      server = [
        "1.1.1.1"
        "1.0.0.1"
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
