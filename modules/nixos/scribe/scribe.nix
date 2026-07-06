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

      # Build context: the Dockerfile + server. Files must be git-tracked for the
      # flake to see them; the image rebuilds when they change.
      scribeSrc = pkgs.runCommand "scribe-src" { } ''
        mkdir -p $out
        cp ${./Dockerfile} $out/Dockerfile
        cp ${./stream_server.py} $out/stream_server.py
      '';
    in
    {
      options.services.scribe = {
        enable = lib.mkEnableOption "Live streaming ASR service (NeMo cache-aware FastConformer, CUDA)";

        model = lib.mkOption {
          type = lib.types.str;
          default = "nvidia/stt_en_fastconformer_hybrid_large_streaming_multi";
          description = ''
            HF model id (SCRIBE_MODEL). Default is the proven streaming-multi
            FastConformer (114M, English). Swap to
            `nvidia/nemotron-speech-streaming-en-0.6b` for higher accuracy.
          '';
        };

        lookaheadMs = lib.mkOption {
          type = lib.types.enum [
            0
            80
            480
            1040
          ];
          default = 480;
          description = "Right-context lookahead ≈ algorithmic latency (SCRIBE_LOOKAHEAD_MS).";
        };

        decoder = lib.mkOption {
          type = lib.types.enum [
            "rnnt"
            "ctc"
          ];
          default = "rnnt";
          description = "Decoder head on the hybrid model (SCRIBE_DECODER); rnnt is more accurate.";
        };

        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/scribe";
          description = "Host dir bind-mounted as the HF/NeMo model cache so weights persist.";
        };
      };

      config = lib.mkIf cfg.enable {
        hardware.nvidia-container-toolkit.enable = true;

        services.local-networking.subdomains = [ subdomain ];

        # NGC API key — needed only to pull the NeMo base image at build time
        # (the models themselves come from HuggingFace, ungated). Get a free key
        # at https://ngc.nvidia.com → Setup → Generate API Key, then set it with:
        #   sops set secrets/main.yaml '["ngc"]["api_key"]' '"nvapi-..."'
        sops = {
          secrets."ngc/api_key" = { };
          templates."scribe-build.env" = {
            mode = "0440";
            content = ''
              NGC_API_KEY=${config.sops.placeholder."ngc/api_key"}
            '';
            restartUnits = [ "build-scribe-image.service" ];
          };
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 root root -"
        ];

        # Log in to nvcr.io and build the thin web layer over the NeMo base. The
        # derived `localhost/scribe:latest` bakes everything in, so the runtime
        # container needs no registry auth. Reruns only when the Dockerfile/server
        # change (or the key rotates). Mirrors build-whisperx-image.
        systemd.services."build-scribe-image" = {
          description = "Build scribe streaming-ASR container image";
          wantedBy = [ "multi-user.target" ];
          before = [ "podman-${subdomain}.service" ];
          # `podman login nvcr.io` needs DNS, so wait for the network — otherwise
          # the boot-time run dies with `lookup nvcr.io: no such host` (exit 125).
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = [
            pkgs.podman
            pkgs.getent
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            EnvironmentFile = config.sops.templates."scribe-build.env".path;
            # First build pulls the ~20GB NeMo base image.
            TimeoutStartSec = "90min";
          };
          # Only the FIRST build needs the network — to pull the nvcr.io NeMo base
          # + apt/pip layers. Once localhost/scribe:latest exists, later boots
          # rebuild from the local cache fully offline (`--pull=missing` never
          # contacts the registry). network-online.target fires before DNS is
          # actually ready on this NetworkManager desktop (wait-online disabled),
          # so when a network build IS needed, wait for real name resolution
          # before logging in — this makes the no-cache first boot succeed too.
          script = ''
            if ! podman image exists localhost/scribe:latest; then
              until getent hosts nvcr.io >/dev/null 2>&1; do
                echo "waiting for DNS to reach nvcr.io..."
                sleep 3
              done
              printf '%s' "$NGC_API_KEY" \
                | podman login nvcr.io --username '$oauthtoken' --password-stdin
            fi
            podman build --pull=missing -f ${scribeSrc}/Dockerfile -t localhost/scribe:latest ${scribeSrc}
          '';
        };

        virtualisation.oci-containers.containers.${subdomain} = {
          autoStart = true;
          image = "localhost/scribe:latest";
          environment = {
            SCRIBE_MODEL = cfg.model;
            SCRIBE_LOOKAHEAD_MS = toString cfg.lookaheadMs;
            SCRIBE_DECODER = cfg.decoder;
            HF_HOME = "/cache/huggingface";
            NEMO_CACHE_DIR = "/cache/nemo";
            # Silence lhotse's `invalid escape sequence` SyntaxWarnings, emitted
            # at import time (before stream_server.py runs).
            PYTHONWARNINGS = "ignore::SyntaxWarning";
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
          # the socket is up. (Same reasoning as the whisperx container.)
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
