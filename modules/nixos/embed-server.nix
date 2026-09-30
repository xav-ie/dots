{
  flake.modules.nixos.praesidium =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.embed-server;
      name = "embed-server";
      containerPort = 8080;
      # harrier-oss-v1-0.6b (Qwen3, last-token pooling). The GGUF carries
      # pooling_type=last and add_eos_token, matching the HF tokenizer's
      # trailing <|endoftext|>; validated against sentence-transformers with
      # ~/Projects/snippet-evals/validate_embed_server.py (cosine >= 0.998).
      modelF16 = pkgs.fetchurl {
        url = "https://huggingface.co/mradermacher/harrier-oss-v1-0.6b-GGUF/resolve/d79decec1ab9442e969e79804515b9c31683d30e/harrier-oss-v1-0.6b.f16.gguf";
        sha256 = "0ykidqrhdcfyws7akrs40v5zv3kkmnk9jwnz5cl9zdaqiwyk3bzk";
      };
      # q8_0 halves the weights (~0.55 GB less VRAM) so scribe fits on the same
      # GPU. validate_embed_server.py: cosine >= 0.998 vs reference, same
      # retrieval scores as f16. Quantized with the CPU llama.cpp, which is
      # cached; the CUDA build would compile from source.
      model = pkgs.runCommand "harrier-oss-v1-0.6b.q8_0.gguf" { } ''
        ${pkgs.llama-cpp.override { cudaSupport = false; }}/bin/llama-quantize ${modelF16} $out q8_0
      '';
    in
    {
      options.services.embed-server = {
        enable =
          lib.mkEnableOption "OpenAI-compatible embedding server for tool search (llama.cpp, CUDA)"
          // {
            default = true;
          };

        port = lib.mkOption {
          type = lib.types.port;
          default = 38978;
          description = "Host port for POST /v1/embeddings, bound to 127.0.0.1.";
        };
      };

      config = lib.mkIf cfg.enable {
        hardware.nvidia-container-toolkit.enable = true;

        virtualisation.podman.enable = true;

        virtualisation.oci-containers.containers.${name} = {
          autoStart = true;
          image = "ghcr.io/ggml-org/llama.cpp:server-cuda@sha256:7494bfc7b553ee14c5c21e1212b52aecbea76db5562168f39f8bdf66250976af";
          ports = [ "127.0.0.1:${cfg.port |> toString}:${containerPort |> toString}" ];
          volumes = [ "${model}:/models/model.gguf:ro" ];
          extraOptions = [
            "--device=nvidia.com/gpu=all"
            "--security-opt=label=disable"
            # Same reasoning as llama-server.nix: the first healthcheck fires
            # while the model is still loading, so a live llama-server process
            # counts as healthy.
            "--health-cmd"
            ''curl -fs --max-time 5 http://localhost:${containerPort |> toString}/health || [ "$(cat /proc/1/comm)" = llama-server ]''
          ];
          cmd = [
            "-m"
            "/models/model.gguf"
            "--embedding"
            "--pooling"
            "last"
            "--host"
            "0.0.0.0"
            "--port"
            (containerPort |> toString)
            "-ngl"
            "99"
            # 1 slot x 1024 tokens; the longest catalogue doc is ~630 tokens. Queries
            # take ~6 ms, so one slot rarely queues; a query arriving mid catalogue
            # re-embed (~6 s) waits for it. Embeddings need a whole input in one ubatch.
            "-c"
            "1024"
            "-np"
            "1"
            "-b"
            "1024"
            "-ub"
            "1024"
          ];
        };

        # First start pulls the multi-GB CUDA image.
        systemd.services."podman-${name}".serviceConfig.TimeoutStartSec = lib.mkForce "30min";
      };
    };
}
