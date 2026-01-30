{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  hmConfig = config.home-manager.users.${config.defaultUser};
  hyprlandEnabled = hmConfig.wayland.windowManager.hyprland.enable or false;
  hyprlockEnabled = hmConfig.programs.hyprlock.enable or false;
in
{
  config = lib.mkMerge [
    # PAM configuration for hyprlock
    (lib.mkIf hyprlockEnabled {
      security.pam.services.hyprlock = { };
    })

    # Service to start Hyprland remotely via SSH
    # Usage: sudo systemctl start hyprland-remote
    (lib.mkIf hyprlandEnabled {
      systemd.services.hyprland-remote = {
        description = "Hyprland on TTY1 (for remote start)";
        after = [ "systemd-user-sessions.service" ];
        conflicts = [ "getty@tty1.service" ];
        serviceConfig = {
          Type = "simple";
          User = config.defaultUser;
          PAMName = "login";
          TTYPath = "/dev/tty1";
          StandardInput = "tty";
          StandardOutput = "tty";
          StandardError = "tty";
          TTYVHangup = true;
          TTYReset = true;
          ExecStart = "${pkgs.writeShellScript "start-hyprland-tty" ''
            # Ensure we're on TTY1
            chvt 1
            exec start-hyprland
          ''}";
          Restart = "no";
        };
      };

      # Unlock GNOME Keyring when using this service
      security.pam.services.login.enableGnomeKeyring = true;
    })

    # XDG portal configuration for hyprland
    (lib.mkIf hyprlandEnabled {
      # TIP: run `nix run nixpkgs#door-knocker` and check that portal
      # implementation has expected support
      xdg.portal =
        let
          inherit (inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system}) xdg-desktop-portal-hyprland;
        in
        {
          enable = true;
          extraPortals = [
            xdg-desktop-portal-hyprland
            pkgs.xdg-desktop-portal-gnome
          ];
          config =
            let
              common = {
                default = [
                  "hyprland"
                  "gnome"
                ];
                # TODO: what kinds of other useful settings can I set?
                # "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
              };
            in
            {
              inherit common;
              hyprland = common;
            };
          # NOTE: configPackages is NOT set here because Hyprland's built-in
          # config overrides our explicit config above. Hyprland's config says
          # "default=hyprland;gtk" which doesn't properly route the Settings
          # interface to GNOME portal. By omitting configPackages, NixOS uses
          # our config which properly routes Settings to gnome.
          # See: GHOSTTY_DARK_MODE_RESEARCH.md
        };
    })
  ];
}
