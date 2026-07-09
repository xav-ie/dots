# arca body — the machine config (imported by ./arca.nix). Headless Hetzner
# Cloud VPS serving the atticd Nix binary cache.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  arca = import ../_lib/arca.nix;
in
{
  imports = [
    # virtio + KVM guest defaults for a Hetzner Cloud VM.
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  # ── Disk (declarative, applied by nixos-anywhere) ───────────────────────────
  # GPT with both a BIOS-boot partition and an ESP, GRUB installed as removable
  # — boots whether Hetzner gives this VM legacy BIOS or UEFI.
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        # BIOS boot partition (GRUB core.img).
        boot = {
          size = "1M";
          type = "EF02";
        };
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
    devices = [ "/dev/sda" ];
  };

  # cpx11 has only 2 GB RAM; give nix operations (rebuild, copy-closure, GC) a
  # swapfile to fall back on instead of OOM-killing the deploy.
  swapDevices = [
    {
      device = "/swapfile";
      # 4 GiB (option is in MiB).
      size = 4096;
      # Fresh random key each boot so swapped-out /run/secrets pages never hit
      # the disk in cleartext.
      randomEncryption.enable = true;
    }
  ];

  # A cache server needs no flake registry / nixPath — not even NixOS's default
  # `nixpkgs` entry, which pins a ~450 MB source into the closure.
  nixpkgs.flake.setFlakeRegistry = false;
  nixpkgs.flake.setNixPath = false;

  # ── Networking ──────────────────────────────────────────────────────────────
  networking = {
    hostName = "arca";
    # Hetzner Cloud hands out the primary IP via DHCP.
    useDHCP = lib.mkDefault true;
    firewall = {
      enable = true;
      # Public 80/443 only (ACME + the cache). SSH is tailnet-only; base trusts
      # the tailscale0 interface.
      allowedTCPPorts = [
        80
        443
      ];
    };
  };

  # ── Users / SSH ─────────────────────────────────────────────────────────────
  users.users.${config.defaultUser} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ arca.sshKey ];
  };
  users.users.root.openssh.authorizedKeys.keys = [ arca.sshKey ];
  # Key-only, no root password login (root key still allowed for provisioning).
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "prohibit-password";
  };
  # The default openFirewall=true would re-add public 22, undoing the port list
  # above — SSH stays tailnet-only.
  services.openssh.openFirewall = false;

  # Security invariants — fail the build if a module default or flake update ever
  # weakens arca's exposure. SSH is tailnet-only with no public fallback, so both
  # "public 22 shut" and "tailnet path intact" must hold, or you're exposed or
  # locked out.
  assertions = [
    {
      # firewall.enable is part of the check: with it off, allowedTCPPorts is
      # moot and 22 would be wide open.
      assertion =
        config.networking.firewall.enable
        && !builtins.elem 22 config.networking.firewall.allowedTCPPorts
        && !lib.any (r: r.from <= 22 && 22 <= r.to) config.networking.firewall.allowedTCPPortRanges;
      message = "arca: public port 22 must stay closed (SSH is tailnet-only). Check networking.firewall.enable and services.openssh.openFirewall.";
    }
    {
      assertion =
        config.services.tailscale.enable
        && builtins.elem "tailscale0" config.networking.firewall.trustedInterfaces;
      message = "arca: SSH reaches this box ONLY over the tailnet — services.tailscale must be enabled and tailscale0 must be a trusted firewall interface, else you'll be locked out.";
    }
    {
      assertion = !config.services.openssh.settings.PasswordAuthentication;
      message = "arca: SSH password authentication must stay disabled (key-only).";
    }
  ];

  # ── Secrets (sops) ──────────────────────────────────────────────────────────
  # arca's own secrets file, encrypted to its host key (the age identity sops-nix
  # derives from /etc/ssh/ssh_host_ed25519_key) + the admin key — so this public
  # box holds no master key and decrypts only its own secret. It skips the shared
  # `linux` sops-common, so no personal secrets are materialised here.
  #
  # secrets/arca.yaml holds one dotenv blob, decrypted to /run/secrets/atticd/env
  # and read by atticd:
  #   ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=...
  #   AWS_ACCESS_KEY_ID=...
  #   AWS_SECRET_ACCESS_KEY=...
  #   AWS_ENDPOINT_URL=https://<account-id>.r2.cloudflarestorage.com
  sops.defaultSopsFile = ../../secrets/arca.yaml;
  sops.secrets."atticd/env" = {
    restartUnits = [ "atticd.service" ];
  };

  # Join the tailnet unattended with an auth key from sops (headless, no
  # interactive `tailscale up`). base already enables tailscale; this supplies
  # the key.
  sops.secrets."tailscale/authkey" = { };
  services.tailscale.authKeyFile = config.sops.secrets."tailscale/authkey".path;

  # ── atticd: the binary cache ────────────────────────────────────────────────
  services.atticd = {
    enable = true;
    environmentFile = config.sops.secrets."atticd/env".path;
    settings = {
      # Fronted by nginx below.
      listen = "127.0.0.1:8080";
      # Blobs on R2 via the S3 backend; AWS_* creds come from the env file.
      storage = {
        type = "s3";
        region = "auto";
        bucket = arca.r2Bucket;
        # endpoint omitted — from AWS_ENDPOINT_URL in the sops env file, keeping
        # the account id out of this public repo.
      };
      # Content-defined chunking for dedup across pushes.
      chunking = {
        "nar-size-threshold" = 65536;
        "min-size" = 16384;
        "avg-size" = 65536;
        "max-size" = 262144;
      };
      garbage-collection = {
        interval = "1 day";
        default-retention-period = "3 months";
      };
    };
  };

  # Bound atticd's memory so a spike is a clean OOM-kill
  systemd.services.atticd.serviceConfig = {
    # ~1.5 GB of the 2 GB box
    MemoryMax = "80%";
    # no swap -> a real overshoot is a clean kill, not a thrash
    MemorySwapMax = "0";
  };

  # ── nginx + Let's Encrypt in front of atticd ────────────────────────────────
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    # Per-IP rate/connection caps (http context). Generous on purpose: a Nix
    # client fires bursts of parallel narinfo/nar requests, so these throttle a
    # single abusive source without choking legit CI pulls. Distributed floods
    # need upstream scrubbing (Hetzner's baseline), not per-IP limits.
    appendHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=cachereq:10m rate=100r/s;
      limit_conn_zone $binary_remote_addr zone=cacheconn:10m;
    '';
    virtualHosts.${arca.domain} = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
        extraConfig = # nginx
          ''
            limit_req zone=cachereq burst=200 nodelay;
            limit_conn cacheconn 100;
            # Real NAR pushes are large but not unbounded; a finite cap bounds
            # upload abuse while allowing legit pushes. Streamed unbuffered, so
            # nginx never spools the body to its own disk.
            client_max_body_size 8g;
            proxy_request_buffering off;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
          '';
      };
    };
  };
  security.acme = {
    acceptTerms = true;
    defaults.email = arca.acmeEmail;
  };

  # ── Ensure the attic caches exist + are public ──────────────────────────────
  # Idempotent oneshot: mints a short-lived admin token (RS256 secret from the
  # sops env) and creates each declared cache public-if-missing. Caches live in
  # atticd's on-box sqlite (/var/lib/atticd), so they survive reboots/deploys but
  # a full reinstall resets them.
  systemd.services.atticd-ensure-caches =
    let
      atticdConfig = (pkgs.formats.toml { }).generate "atticd-admin.toml" config.services.atticd.settings;
      caches = map (c: c.name) (import ../_lib/caches.nix);
      ensure = pkgs.writeShellApplication {
        name = "atticd-ensure-caches";
        runtimeInputs = [
          config.services.atticd.package
          pkgs.attic-client
          pkgs.curl
        ];
        text = # sh
          ''
            export HOME="''${STATE_DIRECTORY:-$(mktemp -d)}"
            # wait for atticd's API to answer (migrations done, DB reachable)
            for _ in $(seq 1 60); do
              curl -sf http://127.0.0.1:8080/ >/dev/null 2>&1 && break
              sleep 2
            done
            # short-lived admin token, signed with the RS256 secret from the env
            token=$(atticadm -f ${atticdConfig} make-token --sub ensure-caches \
              --validity "1 hour" --create-cache '*' --pull '*')
            attic login --set-default local http://127.0.0.1:8080 "$token"
            # Set visibility at creation: `create --public` only needs the create
            # permission, whereas `configure --public` needs one make-token can't grant.
            ${lib.concatMapStringsSep "\n" (c: ''
              attic cache info ${lib.escapeShellArg c} >/dev/null 2>&1 \
                || attic cache create ${lib.escapeShellArg c} --public
            '') caches}
          '';
      };
    in
    {
      description = "Ensure attic caches exist (public)";
      after = [
        "atticd.service"
        "network-online.target"
      ];
      requires = [ "atticd.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = config.sops.secrets."atticd/env".path;
        StateDirectory = "atticd-ensure-caches";
        ExecStart = lib.getExe ensure;
      };
    };

  system.stateVersion = "25.11";
}
