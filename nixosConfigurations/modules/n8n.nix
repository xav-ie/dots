{
  config,
  lib,
  ...
}:
let
  subdomain = "n8n";
  port = 5678;
  inherit (config.services.local-networking) baseDomain;
  # Private URL for UI access (via Tailscale)
  privateHostName = "https://${config.services.n8n.subdomain}.${baseDomain}";
  # Public URL for webhooks (via Cloudflare Tunnel)
  publicWebhookUrl = "https://n8n-webhooks.${baseDomain}";
in
{
  options = {
    services.n8n.subdomain = lib.mkOption {
      type = lib.types.str;
      description = "The subdomain for n8n";
      example = "n8n";
      default = subdomain;
    };
  };

  config = {
    services.local-networking.subdomains = [ config.services.n8n.subdomain ];

    services.n8n = {
      enable = true;
      environment = {
        N8N_PORT = port;
        N8N_HOST = privateHostName;
        N8N_WEBHOOK_URL = "${publicWebhookUrl}/";
        WEBHOOK_URL = "${publicWebhookUrl}/";
        GENERIC_TIMEZONE = "America/New_York";
        N8N_VERSION_NOTIFICATIONS_ENABLED = false;
        N8N_DIAGNOSTICS_ENABLED = false;
      };
    };
  };
}
