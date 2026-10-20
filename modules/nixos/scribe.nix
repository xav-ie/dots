# Consumes the scribe flake's NixOS module (image build + GPU container) and
# layers on the exposure: the local-networking subdomain and Traefik labels.
# The access token is the sops secret scribe/token (secrets/scribe.yaml): the
# server requires it, and scribe-desktop and the extension present it.
{
  # Every linux host gets the token, for scribe-desktop.
  flake.modules.nixos.linux =
    { config, ... }:
    {
      sops.secrets."scribe/token" = {
        sopsFile = ../../secrets/scribe.yaml;
        owner = config.defaultUser;
        mode = "0400";
      };
    };

  flake.modules.nixos.praesidium =
    {
      inputs,
      config,
      lib,
      ...
    }:
    let
      inherit (config.services.local-networking) baseDomain;
      subdomain = "scribe";
    in
    {
      imports = [ inputs.scribe.nixosModules.default ];

      config = lib.mkIf config.services.scribe.enable {
        services.scribe.tokenFile = config.sops.secrets."scribe/token".path;
        services.local-networking.subdomains = [ subdomain ];

        # Wyoming speech to text for Home Assistant. It has no auth, so loopback only.
        virtualisation.oci-containers.containers.scribe.environment.SCRIBE_WYOMING = "0.0.0.0:10300";
        virtualisation.oci-containers.containers.scribe.ports = [ "127.0.0.1:10300:10300" ];

        virtualisation.oci-containers.containers.scribe.labels = {
          "traefik.enable" = "true";
          "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
          "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${subdomain}.${baseDomain}`)";
          "traefik.http.routers.${subdomain}-secure.tls" = "true";
          "traefik.http.routers.${subdomain}-secure.tls.certResolver" = "cloudflare";
          "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
          "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = "8000";
        };
      };
    };
}
