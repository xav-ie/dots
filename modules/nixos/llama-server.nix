{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.services.llama-server;
      inherit (config.services.local-networking) baseDomain;
      subdomain = "llama";
      fullHostName = "${subdomain}.${baseDomain}";
      containerPort = 8080;
    in
    {
      options.services.llama-server = {
        enable = lib.mkEnableOption "llama.cpp server (containerized, CUDA)";

        model = lib.mkOption {
          type = lib.types.str;
          default = "sweepai/sweep-next-edit-1.5B";
          description = "HuggingFace repo to pull the GGUF from (passed to `-hf`)";
        };

        nGpuLayers = lib.mkOption {
          type = lib.types.int;
          default = 99;
          description = "Number of layers to offload to the GPU (99 = all)";
        };

        contextSize = lib.mkOption {
          type = lib.types.int;
          default = 4096;
          description = "Context window size (`-c`). 0 means use model default.";
        };

        parallel = lib.mkOption {
          type = lib.types.int;
          default = 1;
          description = "Number of parallel slots / sequences (`-np`)";
        };

        flashAttention = lib.mkOption {
          type = lib.types.enum [
            "on"
            "off"
            "auto"
          ];
          default = "on";
          description = "Flash attention mode (`-fa <on|off|auto>`)";
        };

        cacheReuse = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = ''
            Reuse N tokens from a previous KV cache when a new prompt shares a
            prefix (`--cache-reuse`). Set to ~256 for big speedups on
            autocomplete-style workloads where consecutive requests share most
            of their context. 0 disables.
          '';
        };

        kvCacheType = lib.mkOption {
          type = lib.types.enum [
            "f32"
            "f16"
            "bf16"
            "q8_0"
            "q5_0"
            "q5_1"
            "q4_0"
            "q4_1"
            "iq4_nl"
          ];
          default = "f16";
          description = ''
            Quantization type for the KV cache, applied to both K and V
            (`-ctk` / `-ctv`). `q8_0` halves cache memory at near-FP16 quality
            and works well with flash attention.
          '';
        };

        image = lib.mkOption {
          type = lib.types.str;
          default = "ghcr.io/ggml-org/llama.cpp:server-cuda";
          description = "llama.cpp server container image";
        };

        dataDir = lib.mkOption {
          type = lib.types.path;
          default = "/var/lib/llama-server";
          description = "Directory for the GGUF model cache";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra arguments appended to llama-server";
        };

        speculation = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable draftless speculative decoding (`--spec-type`)";
          };

          type = lib.mkOption {
            type = lib.types.enum [
              "ngram-cache"
              "ngram-simple"
              "ngram-map-k"
              "ngram-map-k4v"
              "ngram-mod"
            ];
            default = "ngram-simple";
            description = ''
              Speculative decoding strategy. `ngram-simple` is recommended for
              code-edit / refactor workloads.
            '';
          };

          draftNMax = lib.mkOption {
            type = lib.types.nullOr lib.types.int;
            default = null;
            description = "Override `--spec-draft-n-max` (default 16). null = leave unset.";
          };
        };
      };

      config = lib.mkIf cfg.enable {
        hardware.nvidia-container-toolkit.enable = true;

        virtualisation.podman = {
          enable = true;
          dockerCompat = true;
        };

        services.local-networking.subdomains = [ subdomain ];

        systemd.tmpfiles.rules = [
          "d ${cfg.dataDir} 0755 root root -"
        ];

        virtualisation.oci-containers.containers.${subdomain} = {
          autoStart = true;
          inherit (cfg) image;
          volumes = [
            "${cfg.dataDir}:/root/.cache/llama.cpp"
          ];
          extraOptions = [
            "--device=nvidia.com/gpu=all"
            "--security-opt=label=disable"
            "--ipc=host"
            # Replace the image's stock HEALTHCHECK. Podman fires the first
            # healthcheck at t=0, before the GGUF finishes mmap-loading
            # (~25s); the stock `curl /health` then exits non-zero, the
            # transient healthcheck service is marked failed, and
            # switch-to-configuration aborts activation. Our cmd succeeds if
            # /health responds OR if PID 1's comm is still `llama-server`
            # (i.e. the process is alive and just loading).
            "--health-cmd"
            ''curl -fs --max-time 5 http://localhost:${toString containerPort}/health || [ "$(cat /proc/1/comm)" = llama-server ]''
          ];
          cmd = [
            "-hf"
            cfg.model
            "--host"
            "0.0.0.0"
            "--port"
            (toString containerPort)
            "-ngl"
            (toString cfg.nGpuLayers)
            "-c"
            (toString cfg.contextSize)
            "-np"
            (toString cfg.parallel)
          ]
          ++ [
            "-fa"
            cfg.flashAttention
            "-ctk"
            cfg.kvCacheType
            "-ctv"
            cfg.kvCacheType
          ]
          ++ lib.optionals (cfg.cacheReuse > 0) [
            "--cache-reuse"
            (toString cfg.cacheReuse)
          ]
          ++ lib.optionals cfg.speculation.enable [
            "--spec-type"
            cfg.speculation.type
          ]
          ++ lib.optionals (cfg.speculation.enable && cfg.speculation.draftNMax != null) [
            "--spec-draft-n-max"
            (toString cfg.speculation.draftNMax)
          ]
          ++ cfg.extraArgs;
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

        systemd.services."podman-${subdomain}".serviceConfig.TimeoutStartSec = lib.mkForce "30min";
      };
    };
}
