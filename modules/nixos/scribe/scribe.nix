{ inputs, ... }:
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

      # Python env from pyproject.toml + uv.lock: the exact wheels validated by
      # ~/Projects/asr-evals (NeMo 3.0.0, torch 2.14.0), pinned by hash.
      workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
      # torch and the nvidia-* wheels link each other's libraries by relative
      # paths, which break once each wheel is its own store path; the entrypoint
      # puts every nvidia lib dir on LD_LIBRARY_PATH instead. The rest are the
      # driver (injected at run time) and multi-node transports never loaded here.
      fixups =
        final: prev:
        lib.genAttrs (builtins.filter (n: n == "torch" || lib.hasPrefix "nvidia-" n) (
          builtins.attrNames prev
        )) (n: prev.${n}.overrideAttrs { autoPatchelfIgnoreMissingDeps = true; })
        // {
          # Optional TBB threading layer; numba falls back to its own pool.
          numba = prev.numba.overrideAttrs { autoPatchelfIgnoreMissingDeps = [ "libtbb.so.12" ]; };
          antlr4-python3-runtime = prev.antlr4-python3-runtime.overrideAttrs (old: {
            nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem { setuptools = [ ]; };
          });
        };
      pythonSet =
        (pkgs.callPackage inputs.pyproject-nix.build.packages { python = pkgs.python312; }).overrideScope
          (
            lib.composeManyExtensions [
              inputs.pyproject-build-systems.overlays.wheel
              (workspace.mkPyprojectOverlay { sourcePreference = "wheel"; })
              fixups
            ]
          );
      venv = pythonSet.mkVirtualEnv "scribe-env" workspace.deps.default;
      nvidiaLibPath = pkgs.runCommand "scribe-nvidia-libpath" { } ''
        find -L ${venv}/${pkgs.python312.sitePackages}/nvidia -name '*.so*' -printf '%h\n' | sort -u | paste -sd: > $out
      '';

      server = pkgs.runCommand "scribe-server" { } ''
        mkdir -p $out
        cp ${./stream_server.py} $out/stream_server.py
      '';

      # Nix binaries ignore the ld.so cache the NVIDIA CDI hook writes, so point
      # the loader at the driver libraries the hook mounts (NVIDIA_CTK_LIBCUDA_DIR)
      # and the CUDA libraries shipped in the nvidia-* wheels. soundfile dlopens a
      # system libsndfile.
      entrypoint = pkgs.writeShellScript "scribe" ''
        export LD_LIBRARY_PATH="$NVIDIA_CTK_LIBCUDA_DIR:$(< ${nvidiaLibPath}):${lib.getLib pkgs.libsndfile}/lib"
        exec ${venv}/bin/uvicorn stream_server:app --app-dir ${server} --host 0.0.0.0 --port ${toString containerPort}
      '';

      image = pkgs.dockerTools.streamLayeredImage {
        name = "localhost/scribe";
        tag = "latest";
        contents = [ pkgs.cacert ];
        extraCommands = "mkdir -m 1777 tmp";
        config = {
          Cmd = [ entrypoint ];
          Env = [
            "HOME=/tmp"
            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          ];
        };
      };
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

        virtualisation.oci-containers.containers.${subdomain} = {
          autoStart = true;
          imageStream = image;
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

        # Headroom for the first-boot model download before the container is up.
        systemd.services."podman-${subdomain}".serviceConfig.TimeoutStartSec = lib.mkForce "30min";
      };
    };
}
