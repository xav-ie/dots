{
  inputs,
  pkgs,
  ...
}:

let
  # Fetch and patch the Postiz source.
  #
  # Source comes from the `postiz-src` flake input, currently pointed at
  # a local clone (~/Projects/postiz-app) while we test the
  # `fix(mastra): use dedicated postgres schema` change. Once upstream
  # accepts the fix and ships a release, swap the input back to a github
  # ref in flake.nix.
  postizSrc = pkgs.stdenv.mkDerivation {
    name = "postiz-src-patched";
    src = inputs.postiz-src;
    patches = [
      ./integration-fix.patch
      ./pm2-quiet.patch
      ./worker-allowlist.patch
    ];
    phases = [
      "unpackPhase"
      "patchPhase"
      "installPhase"
    ];
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };

  # The app image bakes in var/docker/nginx.conf with `proxy_pass
  # http://localhost:{3000,4200}/`. The pod resolves `localhost` to IPv6 `::1`,
  # where the IPv4-only node backends aren't listening → every request 502s.
  # Patch the upstreams to 127.0.0.1 and mount this over the baked config (see
  # the `nginxConf` arg in instance.nix) — mounting avoids the ~15min image
  # rebuild that editing the source copy would trigger (the COPY precedes the
  # pnpm build layers in Dockerfile.dev).
  patchedNginxConf = pkgs.runCommand "postiz-nginx.conf" { } ''
    substitute ${postizSrc}/var/docker/nginx.conf $out \
      --replace-fail 'http://localhost:3000/' 'http://127.0.0.1:3000/' \
      --replace-fail 'http://localhost:4200/' 'http://127.0.0.1:4200/'
  '';
in
{
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet

    # Instance A. Fronted by a Cloudflare Tunnel + Access at the hostname
    # below; the app port is published to loopback for the tunnel to
    # reach. Holds the social-provider OAuth secrets.
    (import ./instance.nix {
      name = "postiz-a";
      hostName = "postiz.lalala.casa";
      local = false;
      cpuset = "0-3";
      # Providers with a connected integration (from the DB). postiz-b is left
      # at the default (all workers) until its accounts are set up.
      workerProviders = "bluesky,discord,linkedin,mastodon,slack,x";
      publishPort = "127.0.0.1:18801:5000";
      enableSocialProviders = true;
      nginxConf = patchedNginxConf;
    })

    # Instance B. Same tunnel-fronted setup as A.
    (import ./instance.nix {
      name = "postiz-b";
      hostName = "social.aztecahome.com";
      local = false;
      cpuset = "4-7";
      # No social accounts connected yet — run only the 'main' worker.
      # Enabling a provider here later is part of the same change that adds its
      # sops OAuth secrets + enableSocialProviders.
      workerProviders = "";
      publishPort = "127.0.0.1:18800:5000";
      nginxConf = patchedNginxConf;
    })
  ];

  config = {
    # Shared app image. Both instances reference
    # `localhost/postiz-app-patched:latest`, so build it once; each
    # instance's app container orders After this unit.
    systemd.services."build-postiz-image" = {
      description = "Build patched Postiz Docker image";
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [ podman ];

      script = ''
        # Build the Docker image using the patched source and Dockerfile.dev
        podman build -f ${postizSrc}/Dockerfile.dev -t localhost/postiz-app-patched:latest ${postizSrc}
      '';

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    # Required by redis to allow background saves under low memory.
    boot.kernel.sysctl."vm.overcommit_memory" = 1;
  };
}
