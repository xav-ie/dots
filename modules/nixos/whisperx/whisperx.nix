{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.whisperx;
      inherit (config.services.local-networking) baseDomain;
      subdomain = "whisperx";
      fullHostName = "${subdomain}.${baseDomain}";
      containerPort = 8000;
      cfgSecret = config.sops.placeholder;

      # Build context: just the three files the Dockerfile needs, copied into a
      # store path so the image rebuilds when (and only when) they change. The
      # files must be git-tracked for the flake to see them.
      whisperxSrc = pkgs.runCommand "whisperx-src" { } ''
        mkdir -p $out
        cp ${./Dockerfile} $out/Dockerfile
        cp ${./requirements.txt} $out/requirements.txt
        cp ${./constraints.txt} $out/constraints.txt
        cp ${./transcribe_service.py} $out/transcribe_service.py
      '';
    in
    {
      options.services.whisperx = {
        enable = lib.mkEnableOption "WhisperX transcription + diarization service (containerized, CUDA)";

        model = lib.mkOption {
          type = lib.types.str;
          default = "large-v3";
          description = "faster-whisper model size loaded at startup (WHISPERX_MODEL).";
        };

        computeType = lib.mkOption {
          type = lib.types.enum [
            "float16"
            "float32"
            "int8"
          ];
          default = "float16";
          description = "ctranslate2 compute type (WHISPERX_COMPUTE); int8 for low-VRAM/CPU.";
        };

        device = lib.mkOption {
          type = lib.types.enum [
            "cuda"
            "cpu"
          ];
          default = "cuda";
          description = "Inference device (WHISPERX_DEVICE).";
        };

        batchSize = lib.mkOption {
          type = lib.types.int;
          default = 16;
          description = "Transcribe batch size (WHISPERX_BATCH).";
        };

        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/whisperx";
          description = "Host dir bind-mounted as the HF model cache so weights persist.";
        };
      };

      config = lib.mkIf cfg.enable {
        hardware.nvidia-container-toolkit.enable = true;

        services.local-networking.subdomains = [ subdomain ];

        # pyannote diarization is gated on Hugging Face: the token must belong to
        # an account that has accepted the model terms, or the pipeline fails to
        # load at startup. Set it with:
        #   sops set secrets/main.yaml '["whisperx"]["hf_token"]' '"hf_..."'
        sops = {
          secrets."whisperx/hf_token" = { };
          templates."whisperx.env" = {
            mode = "0440";
            content = ''
              HF_TOKEN=${cfgSecret."whisperx/hf_token"}
            '';
            restartUnits = [ "podman-${subdomain}.service" ];
          };
        };

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 root root -"
        ];

        # Build the image once per activation (no-op after the first build unless
        # the Dockerfile/requirements/service change). Mirrors build-postiz-image.
        systemd.services."build-whisperx-image" = {
          description = "Build WhisperX service container image";
          wantedBy = [ "multi-user.target" ];
          before = [ "podman-${subdomain}.service" ];
          path = [ pkgs.podman ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            # First build pulls the ~5GB CUDA torch base + pip-installs whisperx.
            TimeoutStartSec = "60min";
          };
          script = ''
            podman build -f ${whisperxSrc}/Dockerfile -t localhost/whisperx:latest ${whisperxSrc}
          '';
        };

        virtualisation.oci-containers.containers.${subdomain} = {
          autoStart = true;
          image = "localhost/whisperx:latest";
          environmentFiles = [ config.sops.templates."whisperx.env".path ];
          environment = {
            WHISPERX_MODEL = cfg.model;
            WHISPERX_DEVICE = cfg.device;
            WHISPERX_COMPUTE = cfg.computeType;
            WHISPERX_BATCH = toString cfg.batchSize;
            HF_HOME = "/cache/huggingface";
          };
          volumes = [
            "${cfg.dataDir}:/cache"
          ];
          extraOptions = lib.optionals (cfg.device == "cuda") [
            "--device=nvidia.com/gpu=all"
            "--security-opt=label=disable"
            "--ipc=host"
          ];
          # No container healthcheck on purpose: the model weights download +
          # load on first boot takes minutes, during which a stock `curl /health`
          # check exits non-zero, the transient healthcheck unit is recorded as
          # failed, and switch-to-configuration aborts activation. Restart=always
          # recovers from real crashes and Traefik returns 502 until the service
          # is listening — that's the loud signal. (Same reasoning as the Postiz
          # app container.)
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
          after = [ "build-whisperx-image.service" ];
          requires = [ "build-whisperx-image.service" ];
          # Headroom for the first-boot model download (large-v3 + alignment +
          # pyannote) before the container is considered up.
          serviceConfig.TimeoutStartSec = lib.mkForce "30min";
        };
      };
    };
}
