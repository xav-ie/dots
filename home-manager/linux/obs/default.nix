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
          (pkgs.lib.cmakeFeature "CMAKE_C_COMPILER_LAUNCHER" (lib.getExe pkgs.ccache))
          (pkgs.lib.cmakeFeature "CMAKE_CXX_COMPILER_LAUNCHER" (lib.getExe pkgs.ccache))
          (pkgs.lib.cmakeFeature "CMAKE_CUDA_COMPILER_LAUNCHER" (lib.getExe pkgs.ccache))
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
        # Latest source uses ubuntu-x86_64 preset instead of linux-x86_64
        cmakeFlags = builtins.map (
          flag: if flag == "--preset linux-x86_64" then "--preset ubuntu-x86_64" else flag
        ) oldAttrs.cmakeFlags;
      });
in
{
  config = {
    # camera magic
    programs.obs-studio = {
      enable = true;
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
