{
  config,
  lib,
  ...
}:
let
  cfg = config.services.vllm;
  inherit (config.services.local-networking) baseDomain;
  subdomain = "vllm";
  fullHostName = "${subdomain}.${baseDomain}";
  containerPort = 8000;
in
{
  options.services.vllm = {
    enable = lib.mkEnableOption "vLLM inference server (containerized)";

    model = lib.mkOption {
      type = lib.types.str;
      default = "Xenova/sweep-next-edit-1.5B";
      description = "HuggingFace model to serve";
    };

    gpuMemoryUtilization = lib.mkOption {
      type = lib.types.float;
      default = 0.7;
      description = "Fraction of GPU memory to use (0.0-1.0)";
    };

    maxModelLen = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = null;
      description = "Maximum model context length (null for model default)";
    };

    enforceEager = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable CUDA graph capture to save VRAM (slightly slower inference)";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "vllm/vllm-openai:latest";
      description = "vLLM container image";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/vllm";
      description = "Directory for vLLM data (model cache)";
    };

    enablePrefixCaching = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable prefix caching for repeated prompts";
    };

    enableChunkedPrefill = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable chunked prefill for better batching";
    };

    ngramSpeculation = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable ngram speculative decoding (good for edit prediction)";
      };

      lookupMax = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Maximum ngram size for prompt lookup";
      };

      lookupMin = lib.mkOption {
        type = lib.types.int;
        default = 2;
        description = "Minimum ngram size for prompt lookup";
      };

      numTokens = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = "Number of speculative tokens to generate";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Ensure nvidia-container-toolkit is available
    hardware.nvidia-container-toolkit.enable = true;

    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # Register subdomain with traefik
    services.local-networking.subdomains = [ subdomain ];

    # Create data directory for model cache
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/huggingface 0755 root root -"
    ];

    virtualisation.oci-containers.containers.${subdomain} = {
      autoStart = true;
      inherit (cfg) image;
      volumes = [
        "${cfg.dataDir}/huggingface:/root/.cache/huggingface"
      ];
      # GPU passthrough and IPC for CUDA
      extraOptions = [
        "--device=nvidia.com/gpu=all"
        "--security-opt=label=disable"
        "--ipc=host"
      ];
      # vLLM server arguments
      cmd = [
        "--model"
        cfg.model
        "--gpu-memory-utilization"
        (toString cfg.gpuMemoryUtilization)
      ]
      ++ lib.optionals (cfg.maxModelLen != null) [
        "--max-model-len"
        (toString cfg.maxModelLen)
      ]
      ++ lib.optionals cfg.enforceEager [
        "--enforce-eager"
      ]
      ++ lib.optionals cfg.enablePrefixCaching [
        "--enable-prefix-caching"
      ]
      ++ lib.optionals cfg.enableChunkedPrefill [
        "--enable-chunked-prefill"
      ]
      ++ lib.optionals cfg.ngramSpeculation.enable [
        "--speculative-config"
        (builtins.toJSON {
          method = "ngram";
          num_speculative_tokens = cfg.ngramSpeculation.numTokens;
          ngram_prompt_lookup_max = cfg.ngramSpeculation.lookupMax;
          ngram_prompt_lookup_min = cfg.ngramSpeculation.lookupMin;
        })
      ];
      labels = {
        # Expose the container to traefik
        "traefik.enable" = "true";
        # --- Router for HTTPS ---
        "traefik.http.routers.${subdomain}-secure.entrypoints" = "websecure";
        "traefik.http.routers.${subdomain}-secure.rule" = "Host(`${fullHostName}`)";
        "traefik.http.routers.${subdomain}-secure.tls" = "true";
        "traefik.http.routers.${subdomain}-secure.tls.certResolver" = "cloudflare";
        "traefik.http.routers.${subdomain}-secure.service" = "${subdomain}-svc";
        # --- Service Definition ---
        "traefik.http.services.${subdomain}-svc.loadbalancer.server.port" = toString containerPort;
      };
    };

    # Extend timeout for large image + model download
    systemd.services."podman-${subdomain}".serviceConfig.TimeoutStartSec = lib.mkForce "30min";
  };
}
