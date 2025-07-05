{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.dnsmasq;

  dnsmasqConf = pkgs.writeText "dnsmasq.conf" ''
    dnssec
    conf-file=${pkgs.dnsmasq}/share/dnsmasq/trust-anchors.conf
    domain-needed
    conf-dir=/etc/dnsmasq.d/,*.conf
    server=1.1.1.1
    server=1.0.0.1
  '';

  mapA = f: attrs: with builtins; attrValues (mapAttrs f attrs);
in
{
  services.dnsmasq = {
    enable = false;
    package = pkgs.dnsmasq;
    bind = "127.0.0.1";
    port = 53;
  };

  launchd.daemons.dnsmasq = lib.mkIf cfg.enable {
    serviceConfig.ProgramArguments = lib.mkForce (
      [
        "${cfg.package}/bin/dnsmasq"
        "--listen-address=${cfg.bind}"
        "--port=${toString cfg.port}"
        "--keep-in-foreground"
        "--conf-file=${dnsmasqConf}"
      ]
      ++ (mapA (domain: addr: "--address=/${domain}/${addr}") cfg.addresses)
    );
  };

  environment.etc."dnsmasq.d/.keep".text = "";
}
