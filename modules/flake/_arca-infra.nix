# OpenTofu (terranix) config for arca's cloud resources: a Hetzner Cloud VM +
# firewall, a Cloudflare R2 bucket for the atticd blobs, and a DNS-only A record
# so pushes bypass Cloudflare's 100 MB proxy cap. Provisions the box and DNS;
# NixOS is installed onto the resulting IP separately with `nixos-anywhere`.
_:
let
  arca = import ../_lib/arca.nix;
in
{
  terraform.required_providers = {
    hcloud = {
      source = "hetznercloud/hcloud";
      version = "~> 1.49";
    };
    cloudflare = {
      source = "cloudflare/cloudflare";
      version = "~> 5.0";
    };
  };

  # State lives in a dedicated `arca-tfstate` R2 bucket. R2 speaks S3, so use the
  # s3 backend with the AWS-only checks disabled. The endpoint is read from
  # AWS_ENDPOINT_URL_S3 (kept out of the repo, like atticd's). `use_lockfile`
  # keeps a lock object in the bucket, so no DynamoDB is needed.
  terraform.backend.s3 = {
    bucket = "arca-tfstate";
    key = "arca.tfstate";
    region = "auto";
    use_path_style = true;
    use_lockfile = true;
    skip_credentials_validation = true;
    skip_metadata_api_check = true;
    skip_region_validation = true;
    skip_requesting_account_id = true;
    skip_s3_checksum = true;
  };

  # Supplied at apply time as TF_VAR_* (tokens from sops). Tokens are sensitive so
  # they stay out of the plan output and logs.
  variable = {
    hcloud_token.sensitive = true;
    cloudflare_token.sensitive = true;
    cloudflare_account_id = { };
    cloudflare_zone_id = { };
    cache_subdomain.default = arca.cacheSubdomain;
    # Hillsboro, US-West; e.g. nbg1 for EU.
    hetzner_location.default = "hil";
    # US locations use CPX (AMD) / CAX (ARM), not the EU-only CX line.
    # cpx11 = 2 vCPU / 2 GB / 40 GB, ~€4.35/mo.
    hetzner_server_type.default = "cpx11";
    r2_bucket.default = arca.r2Bucket;
    # West North America; e.g. weur for EU.
    r2_location.default = "wnam";
  };

  provider = {
    hcloud.token = "\${var.hcloud_token}";
    cloudflare.api_token = "\${var.cloudflare_token}";
  };

  resource = {
    hcloud_ssh_key.arca = {
      name = "arca";
      public_key = arca.sshKey;
    };

    # Public 80/443 only; SSH (22) is reachable solely over the tailnet.
    hcloud_firewall.arca = {
      name = "arca";
      rule = [
        {
          direction = "in";
          protocol = "tcp";
          port = "80";
          source_ips = [
            "0.0.0.0/0"
            "::/0"
          ];
        }
        {
          direction = "in";
          protocol = "tcp";
          port = "443";
          source_ips = [
            "0.0.0.0/0"
            "::/0"
          ];
        }
      ];
    };

    hcloud_server.arca = {
      name = "arca";
      # Any Linux with kexec works; nixos-anywhere replaces it with NixOS.
      image = "debian-12";
      server_type = "\${var.hetzner_server_type}";
      location = "\${var.hetzner_location}";
      ssh_keys = [ "\${hcloud_ssh_key.arca.id}" ];
      firewall_ids = [ "\${hcloud_firewall.arca.id}" ];
      public_net = {
        ipv4_enabled = true;
        ipv6_enabled = true;
      };
    };

    cloudflare_r2_bucket.nix_cache = {
      account_id = "\${var.cloudflare_account_id}";
      name = "\${var.r2_bucket}";
      location = "\${var.r2_location}";
    };

    # DNS-only (proxied = false) → uploads go straight to the box, dodging
    # Cloudflare's 100 MB request-body limit that would 413 attic pushes.
    cloudflare_dns_record.cache = {
      zone_id = "\${var.cloudflare_zone_id}";
      name = "\${var.cache_subdomain}";
      type = "A";
      content = "\${hcloud_server.arca.ipv4_address}";
      ttl = 300;
      proxied = false;
    };
  };

  # Feed this IP to `nixos-anywhere ... root@<ip>`.
  output.arca_ipv4.value = "\${hcloud_server.arca.ipv4_address}";
}
