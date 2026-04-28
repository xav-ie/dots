{
  config,
  lib,
  pkgs,
  ...
}:
let
  hmConfig = config.home-manager.users.${config.defaultUser};
  hyprlandEnabled = hmConfig.wayland.windowManager.hyprland.enable or false;
in
lib.mkIf hyprlandEnabled {
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        # Launch start-hyprland through a login zsh so /etc/profile and
        # ~/.profile (where home.sessionVariables ends up — including the
        # NVIDIA env vars) get sourced before the compositor starts. This
        # mirrors the TTY login flow exactly.
        command = "${lib.getExe pkgs.greetd.tuigreet} --time --remember --remember-session --cmd 'zsh -lc start-hyprland'";
        user = "greeter";
      };
    };
  };
}
