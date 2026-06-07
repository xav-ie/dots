{
  flake.modules.nixos.linux = {
    config = {
      security.rtkit.enable = true;

      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        jack.enable = true;
        # Disable Bluetooth autoswitch due to WirePlumber 0.5.13 bug
        # https://gitlab.freedesktop.org/pipewire/wireplumber/-/issues/682
        # This prevents crashes when AirPods connect. Manual profile switching
        # may be needed for microphone use.
        wireplumber.extraConfig."50-disable-bluetooth-autoswitch" = {
          "wireplumber.settings" = {
            "bluetooth.autoswitch-to-headset-profile" = false;
          };
        };
      };
    };
  };
}
