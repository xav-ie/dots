{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  obs-advanced-masks = pkgs.callPackage ./obs-advanced-masks.nix { };
  obs-stroke-glow-shadow = pkgs.callPackage ./obs-stroke-glow-shadow.nix { };
  obs-backgroundremoval = # remove background
    (pkgs.obs-studio-plugins.obs-backgroundremoval.override {
      # Override ONNX Runtime to enable TensorRT execution provider with ccache
      onnxruntime = pkgs.onnxruntime.overrideAttrs (old: {
        cmakeFlags = old.cmakeFlags ++ [
          # Enable ccache via CMAKE_*_COMPILER_LAUNCHER
          (pkgs.lib.cmakeFeature "CMAKE_C_COMPILER_LAUNCHER" "${pkgs.ccache}/bin/ccache")
          (pkgs.lib.cmakeFeature "CMAKE_CXX_COMPILER_LAUNCHER" "${pkgs.ccache}/bin/ccache")
          (pkgs.lib.cmakeFeature "CMAKE_CUDA_COMPILER_LAUNCHER" "${pkgs.ccache}/bin/ccache")
        ];
        # Set ccache directory
        preConfigure =
          (old.preConfigure or "")
          # sh
          + ''
            export CCACHE_DIR=/var/cache/ccache
            export CCACHE_SLOPPINESS=random_seed
            export CCACHE_MAXSIZE=20G
            export CCACHE_COMPRESS=true
          '';
      });
    }).overrideAttrs
      (oldAttrs: {
        src = inputs.obs-backgroundremoval;
        inherit ((builtins.fromJSON (builtins.readFile "${inputs.obs-backgroundremoval}/buildspec.json")))
          version
          ;
        nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [ pkgs.pkg-config ];
        # Remove preset - the CMakeLists.txt defaults (USE_PKGCONFIG=ON, VCPKG_TARGET_TRIPLET="")
        # are already correct for Nix builds. Also clear custom build/install phases
        # since they reference build_x86_64 which the preset created.
        cmakeFlags = builtins.filter (flag: !(lib.hasPrefix "--preset" flag)) oldAttrs.cmakeFlags;
        buildPhase = null;
        installPhase = null;
        postBuild = ''
          echo "Building benchmark..."
          cmake -B bench-build -S $src/benchmark -DCMAKE_BUILD_TYPE=Release
          cmake --build bench-build
          echo "Running benchmark..."
          ./bench-build/bench $src/benchmark/test-clip.mp4 -m $src/benchmark/tiny.onnx
        '';
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
      plugins =
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
          # # allow caputre from wlroots-based compositors
          # wlrobs
        ]
        ++ [
          obs-advanced-masks
          obs-backgroundremoval
          obs-stroke-glow-shadow
        ];
    };

    # Copy obs-shaderfilter examples to local config directory
    xdg.configFile."obs-studio/shaders/".source =
      "${pkgs.obs-studio-plugins.obs-shaderfilter}/share/obs/data/obs-plugins/obs-shaderfilter/examples";
  };
}
