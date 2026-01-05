{
  config,
  lib,
  pkgs,
  ...
}:
let
  noisetorchInit = pkgs.writeNuApplication {
    name = "noisetorch-init";
    runtimeInputs = [ pkgs.pulseaudio ];
    text = builtins.readFile ./noisetorch-init.nu;
  };
in
{
  config = {
    # Enable noisetorch with setcap wrapper for CAP_SYS_RESOURCE capability
    programs.noisetorch.enable = true;

    # Auto-start noisetorch as a user service (runs in user session context)
    # bindsTo ensures noisetorch restarts if pipewire-pulse restarts, keeping the virtual mic device in sync
    systemd.user.services.noisetorch = lib.mkIf config.programs.noisetorch.enable {
      description = "NoiseTorch Noise Suppression";
      after = [ "pipewire-pulse.service" ];
      bindsTo = [ "pipewire-pulse.service" ];
      wantedBy = [ "pipewire-pulse.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe noisetorchInit;
        ExecStop = "/run/wrappers/bin/noisetorch -u";
        # Block network access so noisetorch's update check fails instantly
        PrivateNetwork = true;
      };
    };
  };
}
