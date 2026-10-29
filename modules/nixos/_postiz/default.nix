{
  inputs,
  pkgs,
  ...
}:

let
  # Fetch and patch the Postiz source.
  #
  # Source comes from the `postiz-src` flake input: a fork branch carrying
  # `fix(mastra): use dedicated postgres schema` on top of an upstream
  # release. Once upstream accepts the fix, point the input back at an
  # upstream tag in flake.nix.
  postizSrc = pkgs.stdenv.mkDerivation {
    name = "postiz-src-patched";
    src = inputs.postiz-src;
    patches = [
      ./pm2-quiet.patch
      ./pwa.patch
      ./quicktime-upload.patch
      ./repeat-intervals.patch
      ./worker-allowlist.patch
    ];
    nativeBuildInputs = with pkgs; [
      imagemagick
      librsvg
    ];
    # Home-screen icons for pwa.patch's manifest: the logo at 60% on the
    # dark background, inside the safe zone of a maskable icon.
    postPatch = ''
      # Podman here resolves no short image names; qualify the base image.
      substituteInPlace Dockerfile.dev --replace-fail 'FROM node:' 'FROM docker.io/library/node:'

      mkdir -p apps/frontend/public/pwa
      for spec in icon-192:192 icon-512:512 apple-touch-icon:180; do
        name=''${spec%:*} size=''${spec#*:} logo=$(( ''${spec#*:} * 60 / 100 ))
        rsvg-convert -w $logo -h $logo --keep-aspect-ratio \
          apps/frontend/public/postiz.svg -o logo.png
        magick -size ''${size}x''${size} xc:'#0e0e0e' logo.png \
          -gravity center -composite apps/frontend/public/pwa/$name.png
      done
      rm logo.png
    '';
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
  #
  # The `Cookie` rewrite implements passwordless access: Cloudflare Access is
  # the only identity gate we want, so requests that arrive without an `auth`
  # cookie get a pre-minted, non-expiring one for the instance's single user.
  # It has to be the *cookie* rather than the `Auth` header because the Next
  # SSR path (`internalFetch`) reads `cookies()` and talks to the backend
  # directly on :3000, bypassing nginx entirely. `$postiz_cookie` is defined by
  # the per-instance /config/auth-map.conf, which holds the token (a sops
  # template; see instance.nix).
  patchedNginxConf = pkgs.runCommand "postiz-nginx.conf" { } ''
    substitute ${postizSrc}/var/docker/nginx.conf $out \
      --replace-fail 'http://localhost:3000/' 'http://127.0.0.1:3000/' \
      --replace-fail 'http://localhost:4200/' 'http://127.0.0.1:4200/' \
      --replace-fail 'http {' 'http {
      include                     /config/auth-map.conf;' \
      --replace-fail 'proxy_set_header Auth $http_auth;' 'proxy_set_header Auth $http_auth;
            proxy_set_header Cookie $postiz_cookie;'
  '';
in
{
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet

    # Instance A. Fronted by a Cloudflare Tunnel + Access at the hostname
    # below; the tunnel reaches it through traefik. Holds the
    # social-provider OAuth secrets.
    (import ./instance.nix {
      name = "postiz-a";
      hostName = "postiz.lalala.casa";
      local = false;
      cpuset = "0-3";
      # Providers with a connected integration (from the DB). postiz-b is left
      # at the default (all workers) until its accounts are set up.
      workerProviders = "bluesky,discord,linkedin,mastodon,slack,x";
      socialProviders = [
        "discord"
        "linkedin"
        "mastodon"
        "slack"
        "x"
      ];
      nginxConf = patchedNginxConf;
    })

    # Instance B. Same tunnel-fronted setup as A.
    (import ./instance.nix {
      name = "postiz-b";
      hostName = "social.aztecahome.com";
      local = false;
      cpuset = "4-7";
      # A provider is enabled together with its sops OAuth secrets.
      workerProviders = "facebook,instagram";
      socialProviders = [ "facebook" ];
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
