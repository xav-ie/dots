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
in
{
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet
    ./temporal-opensearch-image.nix

    # Instance A. Fronted by a Cloudflare Tunnel + Access at the hostname
    # below; the app port is published to loopback for the tunnel to
    # reach. Holds the social-provider OAuth secrets.
    (import ./instance.nix {
      name = "postiz-a";
      hostName = "postiz.lalala.casa";
      local = false;
      cpuset = "0-3";
      publishPort = "127.0.0.1:18801:5000";
      enableSocialProviders = true;
    })

    # Instance B. Same tunnel-fronted setup as A.
    (import ./instance.nix {
      name = "postiz-b";
      hostName = "social.aztecahome.com";
      local = false;
      cpuset = "4-7";
      publishPort = "127.0.0.1:18800:5000";
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
