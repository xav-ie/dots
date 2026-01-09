{
  config,
  lib,
  pkgs,
  ...
}:
let
  subdomain = "n8n";
  port = 5678;
  inherit (config.services.local-networking) baseDomain;

  n8n = pkgs.pkgs-bleeding.n8n.overrideAttrs (old: rec {
    version = "2.3.0";
    src = pkgs.fetchFromGitHub {
      owner = "n8n-io";
      repo = "n8n";
      tag = "n8n@${version}";
      hash = "sha256-6VfoT8Rw2c46ugSpW1IHJPSHTWnphNn0MG1XDhrPeBg=";
    };
    pnpmDeps = pkgs.pkgs-bleeding.fetchPnpmDeps {
      inherit (old) pname;
      inherit version src;
      pnpm = pkgs.pkgs-bleeding.pnpm_10;
      fetcherVersion = 3;
      hash = "sha256-wSKxoxWys3gf++yTDr/XBadW9bq/w/NKPGUZpbAPe+I=";
    };
  });
  # Private URL for UI access (via Tailscale)
  editorBaseUrl = "https://${config.services.n8n.subdomain}.${baseDomain}";
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
    users.users.n8n = {
      isSystemUser = true;
      group = "n8n";
      description = "n8n workflow automation service user";
      home = "/var/lib/n8n";
      createHome = false;
    };
    users.groups.n8n = { };

    sops.secrets."n8n/encryption_key" = {
      owner = "n8n";
      group = "n8n";
      restartUnits = [ "n8n.service" ];
    };

    sops.secrets."n8n/github_webhook_secret_1" = {
      owner = "n8n";
      group = "n8n";
    };

    services.local-networking.subdomains = [ config.services.n8n.subdomain ];

    services.n8n = {
      enable = true;
      package = n8n;
      environment = {
        N8N_PORT = toString port;
        N8N_HOST = "127.0.0.1";
        N8N_EDITOR_BASE_URL = editorBaseUrl;
        WEBHOOK_URL = "${publicWebhookUrl}/";
        N8N_PROXY_HOPS = "1";
        N8N_ENCRYPTION_KEY_FILE = config.sops.secrets."n8n/encryption_key".path;
        GENERIC_TIMEZONE = "America/New_York";
        N8N_VERSION_NOTIFICATIONS_ENABLED = false;
        N8N_DIAGNOSTICS_ENABLED = false;
        N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true";
        # Allow all builtin Node.js modules in Code nodes
        NODE_FUNCTION_ALLOW_BUILTIN = "*";
      };
    };

    # Override DynamicUser to use static user for SOPS secret access
    systemd.services.n8n.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "n8n";
      Group = "n8n";
    };
  };
}
