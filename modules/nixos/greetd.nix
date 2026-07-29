{
  flake.modules.nixos.linux =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      hmConfig = config.home-manager.users.${config.defaultUser};
      hyprlandEnabled = hmConfig.wayland.windowManager.hyprland.enable or false;
      # Launch start-hyprland through a login zsh so /etc/profile and ~/.profile
      # (where home.sessionVariables ends up — including the NVIDIA env vars) get
      # sourced before the compositor starts. This mirrors the TTY login flow
      # exactly.
      sessionCommand = "zsh -lc start-hyprland";
    in
    lib.mkIf hyprlandEnabled {
      services.greetd = {
        enable = true;
        settings = {
          default_session = {
            command = "${lib.getExe pkgs.tuigreet} --time --remember --remember-session --cmd '${sessionCommand}'";
            user = "greeter";
          };
        };
      };

      # Boot entry that skips the greeter and drops straight into the session,
      # for rebooting a machine you can't type a password into. Selected for a
      # single boot via `just reboot-auto-login`; the next boot is normal again.
      specialisation.autologin.configuration = {
        services.greetd.settings.initial_session = {
          command = sessionCommand;
          user = config.defaultUser;
        };
      };
    };
}
