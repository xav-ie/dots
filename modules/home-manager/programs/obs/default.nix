# TODO: is it bad to pass attrs? nixpkgs specifies all attrs
{ pkgs, ... }@attrs:
let
  obs-advanced-masks = pkgs.callPackage ./obs-advanced-masks.nix { inherit attrs; };
  obs-stroke-glow-shadow = pkgs.callPackage ./obs-stroke-glow-shadow.nix { inherit attrs; };
in
{
  # camera magic 
  programs.obs-studio = {
    enable = true;
    plugins =
      with pkgs.obs-studio-plugins;
      [
        # droidcam-obs # use phone as camera
        input-overlay # overlays mouse/keyboard inputs
        # looking-glass-obs # native looking glass capture
        obs-3d-effect # 3d effects on sources
        obs-backgroundremoval # remove background
        obs-composite-blur # blur a source
        # obs-fbc # capture screen with nvidia fbc? not sure if useful
        obs-gradient-source # gradient background color sources
        obs-move-transition # move transitions
        # obs-ndi # audio/video enc/dec through lan with NDI protocol
        obs-pipewire-audio-capture # use pipewire audio/video source; desktop capture
        obs-shaderfilter # cool source filters, also includes face-tracking
        obs-source-clone # clone sources for applying effects
        # obs-websocket # remote control obs... I think this is built-in?
        wlrobs # make obs work with wayland
      ]
      ++ [
        obs-advanced-masks
        obs-stroke-glow-shadow
      ];
    # TODO: why does not work, but the above `let...in` does?
    #   ++ [
    #   pkgs.callPackage ./obs-advanced-masks.nix { inherit attrs; }
    # ];
  };
}
