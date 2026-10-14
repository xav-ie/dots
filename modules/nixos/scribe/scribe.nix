{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.scribe;
      inherit (config.services.local-networking) baseDomain;
      subdomain = "scribe";
      fullHostName = "${subdomain}.${baseDomain}";
      containerPort = 8000;

      # Build context: the Dockerfile plus its inputs, copied into a single
      # store path so the runtime image rebuilds when (and only when) they
      # change. The files must be git-tracked for the flake to see them.
      scribeSrc = pkgs.runCommand "scribe-src" { } ''
        mkdir -p $out
        cp ${./Dockerfile} $out/Dockerfile
        cp ${./pyproject.toml} $out/pyproject.toml
        cp ${./uv.lock} $out/uv.lock
        cp ${./stream_server.py} $out/stream_server.py
        cp ${./ui.html} $out/ui.html
      '';
    in
    {
      options.services.scribe = {
        enable = lib.mkEnableOption "Live streaming ASR service (NeMo parakeet-unified, CUDA)";

        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/scribe";
          description = "Host dir bind-mounted as /cache: HF/NeMo model cache, plus saved recordings under recordings/.";
        };
      };

      config = lib.mkIf cfg.enable {
        hardware.nvidia-container-toolkit.enable = true;

        services.local-networking.subdomains = [ subdomain ];

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 root root -"
        ];

        # Build the image once per activation (no-op after the first build
        # unless the Dockerfile/workspace change). Mirrors build-whisperx-image.
        # The python env (torch 2.14 + the nvidia-* cu13 wheels pinned by
        # uv.lock, ~3.9 GiB) is assembled by `uv sync` inside the image instead
        # of uv2nix, so it never enters the system closure — and podman no
        # longer double-stores a streamed nix image after load.
        systemd.services."build-scribe-image" = {
          description = "Build scribe streaming ASR container image";
          wantedBy = [ "multi-user.target" ];
          before = [ "podman-${subdomain}.service" ];
          path = [ pkgs.podman ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # First build pulls python:3.12-slim + the pinned CUDA wheels.
            TimeoutStartSec = "60min";
          };
          script = ''
            podman build -f ${scribeSrc}/Dockerfile -t localhost/${subdomain}:latest ${scribeSrc}
          '';
        };

        virtualisation.oci-containers.containers.${subdomain} = {
          autoStart = true;
          image = "localhost/scribe:latest";
          environment = {
            HF_HOME = "/cache/huggingface";
            NEMO_CACHE_DIR = "/cache/nemo";
            NUMBA_CACHE_DIR = "/tmp";
            # Silence lhotse's `invalid escape sequence` SyntaxWarnings, emitted
            # at import time (before stream_server.py runs).
            PYTHONWARNINGS = "ignore::SyntaxWarning";
            # Shares an 8 GB GPU with embed-server; growable segments cut the
            # fragmentation that makes a near-full card OOM on small allocations.
            PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
          };
          volumes = [
            "${cfg.dataDir}:/cache"
          ];
          extraOptions = [
            "--device=nvidia.com/gpu=all"
            "--security-opt=label=disable"
            "--ipc=host"
          ];
          # No container healthcheck on purpose: first-boot model download + load
          # takes minutes, during which a stock check would fail and abort
          # activation. Restart=always recovers from crashes; Traefik 502s until
          # the socket is up.
          labels = {
            "traefik.enable" = "true";
            "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
            "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
            "traefik.http.routers.${subdomain}-secure.tls" = "true";
            "traefik.http.routers.${subdomain}-secure.tls.certResolver" = "cloudflare";
            "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
            "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = toString containerPort;
          };
        };

        systemd.services."podman-${subdomain}" = {
          after = [ "build-scribe-image.service" ];
          requires = [ "build-scribe-image.service" ];
          # Headroom for the first-boot model download before the container is up.
          serviceConfig.TimeoutStartSec = lib.mkForce "30min";
        };
      };
    };
}
