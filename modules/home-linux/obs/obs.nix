{
  flake.modules.homeManager.linux =
    {
      inputs,
      lib,
      pkgs,
      ...
    }:
    let
      # These plugins build with -Werror against an obs-studio whose API has
      # moved on, and gcc 16 promoted two of their warnings to errors: discarded
      # `const` qualifiers, and calls to the now-deprecated
      # obs_properties_add_button. Relax both for every plugin rather than per
      # plugin — the next one to drift fails the same two ways.
      relaxWerror =
        p:
        p.overrideAttrs (old: {
          env = (old.env or { }) // {
            NIX_CFLAGS_COMPILE = toString [
              (old.env.NIX_CFLAGS_COMPILE or "")
              "-Wno-error=discarded-qualifiers"
              "-Wno-error=deprecated-declarations"
            ];
          };
        });
      obs-shaderfilter = relaxWerror pkgs.obs-studio-plugins.obs-shaderfilter;
      obs-advanced-masks = pkgs.callPackage ./_pkgs/obs-advanced-masks.nix { };
      obs-stroke-glow-shadow = pkgs.callPackage ./_pkgs/obs-stroke-glow-shadow.nix { };
      obs-backgroundremoval = # remove background
        (pkgs.obs-studio-plugins.obs-backgroundremoval.override {
          # The plugin picks its execution provider at runtime from whatever the
          # linked ONNX Runtime offers, so the GPU path only exists if that
          # runtime was built with CUDA. Take it from `pkgs-bleeding-cuda` (the
          # host's `pkgs` is deliberately CUDA-free so opencv/openvino/firefox
          # stay cache hits), spelled exactly as `speech/hyprwhspr.nix` spells
          # it so both consumers share one derivation instead of each compiling
          # their own. OpenVINO is Intel-only inference, unused on this GPU, and
          # dropping it takes a full opencv build with it.
          onnxruntime = pkgs.pkgs-bleeding-cuda.onnxruntime.override { openvinoSupport = false; };
        }).overrideAttrs
          (oldAttrs: {
            src = inputs.obs-backgroundremoval;
            version = "${inputs.obs-backgroundremoval}/VERSION" |> builtins.readFile |> lib.strings.trim;
            nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ pkgs.pkg-config ];
            cmakeFlags = oldAttrs.cmakeFlags |> builtins.filter (flag: !(lib.hasPrefix "--preset" flag));
            buildPhase = null;
            installPhase = null;
            # #787 is stacked on #785 — its patch carries #785's two commits
            # (benchmark harness, ORT spin-wait) as well as its own, so applying
            # both double-creates `benchmark/` and `src/pipeline-helpers.h` and
            # the second patch is rejected. #786 is independent of both.
            patches = (oldAttrs.patches or [ ]) ++ [
              (pkgs.fetchpatch {
                name = "optimize-inference-preprocessing.patch";
                url = "https://github.com/royshil/obs-backgroundremoval/pull/787.diff";
                hash = "sha256-qXwcU+fnUUZePbTdfRbW3ktRMuc/bYF4KGCE5zlO7kM=";
              })
              (pkgs.fetchpatch {
                name = "fix-race-and-reduce-copies.patch";
                url = "https://github.com/royshil/obs-backgroundremoval/pull/786.diff";
                hash = "sha256-fv2mkDUZnYN4oSY1jT8pgzNOLtZ8oNgnwiYNSd5jR5g=";
              })
            ];
          });
    in
    {
      config = {
        # camera magic
        programs.obs-studio = {
          enable = true;
          # Prevent OpenMP threads (from ONNX Runtime / OpenCV) from busy-spinning
          # at barriers. Without this, OBS burns ~90% CPU on gomp_barrier_wait_end
          # even though the actual inference runs on GPU via CUDA.
          package = pkgs.obs-studio.overrideAttrs (old: {
            postFixup = (old.postFixup or "") + ''
              wrapProgram $out/bin/obs \
                --set OMP_WAIT_POLICY passive
            '';
          });
          plugins = map relaxWerror (
            with pkgs.obs-studio-plugins;
            [
              # # use phone as camera
              # droidcam-obs
              # # overlays mouse/keyboard inputs
              # input-overlay
              # looking-glass-obs # native looking glass capture
              obs-3d-effect # 3d effects on sources
              obs-composite-blur # blur a source
              # gradient background color sources
              obs-gradient-source
              # move transitions
              obs-move-transition
              # # audio/video enc/dec through lan with NDI protocol
              # obs-ndi
              # use pipewire audio/video source; desktop capture
              obs-pipewire-audio-capture
              # see https://github.com/exeldro/obs-shaderfilter/issues/58
              # cool source filters, also includes face-tracking
              obs-shaderfilter
              # clone sources for applying effects
              obs-source-clone
              # # allow capture from wlroots-based compositors
              # wlrobs
            ]
            ++ [
              obs-advanced-masks
              obs-backgroundremoval
              obs-stroke-glow-shadow
            ]
          );
        };

        # Copy obs-shaderfilter examples to local config directory
        xdg.configFile."obs-studio/shaders/".source =
          "${obs-shaderfilter}/share/obs/data/obs-plugins/obs-shaderfilter/examples";
      };
    };
}
