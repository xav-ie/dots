{ lib, pkgs, ... }:
{
  imports = [
    ./cliphist
    ./dconf
    ./firefox
    ./gtk
    ./hyprland
    ./nemo
    ./obs
    ./rofi
    ./sioyek
    ./swaynotificationcenter
    ./systemd
    ./waybar
  ];

  config = {
    home = {
      packages =
        (with pkgs; [
          ################################
          # in triage - try to minimize this list
          ################################
          asciinema # record shell sessions and share easily
          age # the new PGP
          clipboard-jh # a really awesome clipboard
          home-assistant
          manix
          # nodePackages."webtorrent-cli"
          xidel # like jq but for html and much more advanced.
          # prusa-slicer                # does not launch currently
          python312Packages."adblock"
          subliminal-custom # for mpv autosub script (custom 2.4.0 with knowit)
          xdg-utils # xdg-open, xdg-mime, xdg-email, etc.
          wf-recorder
          # wtype # xdotool for wayland; used as part of rofi-rbw for typing
          # https://github.com/marionebl/svg-term-cli
          # allows asciinema recordings to be exported to svg... this could be
          # pretty indespensable if you would like ANSI escape sequences to be
          # interpreted by GH
          ################################
          # universal utils
          ################################
          cmake
          file # magic number reader
          gcc
          # gnumake # provides `make`, which should already be provided?
          #ninja
          vim
          wget
          ################################
          # user programs
          ################################
          bitwarden-desktop
          chromium
          # discord
          noisetorch # noise filter
          pavucontrol # audio mixer
          playerctl # play, pause, next
          pulseaudio # provides pactl for volume control
          # qutebrowser
        ])
        ++ (with pkgs.pkgs-bleeding; [
          # needs latest security releases
          google-chrome
          signal-desktop
        ])
        ++ (with pkgs.pkgs-mine; [
          move-active
          record
          record-section
          rofi-powermenu
          zenity-askpass
        ]);

      # The state version is required and should stay at the version you
      # originally installed.
      stateVersion = "23.11";
      sessionVariables = {
        # va-api driver to use 'nvidia', '', ...
        GBM_BACKEND = "nvidia-drm";
        LIBVA_DRIVER_NAME = "nvidia";
        NH_ELEVATION_PROGRAM = "/run/wrappers/bin/sudo-askpass";
        NIXOS_OZONE_WL = "1";
        SUDO_ASKPASS = lib.getExe pkgs.pkgs-mine.zenity-askpass;
        WLR_NO_HARDWARE_CURSORS = "1";
        XDG_CONFIG_HOME = "/home/x/.config";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      };
    };
    programs = {
      rbw.enable = true; # unnofficial bitwarden client
      lazygit.enable = true; # easy git tui
      himalaya.enable = true; # email
    };

    services = {
      # Disabled - causes excessive CPU usage from continuous device discovery
      # Use `bluetoothctl` or `bluetuith` for manual Bluetooth management instead
      # blueman-applet.enable = true;
      network-manager-applet.enable = true;
      swww.enable = true; # wallpaper
      udiskie.enable = true;
    };

    # TODO: somehow make mac support this
    xdg.mimeApps.enable = true;

    # Portal configuration for home-manager
    # When home-manager's Hyprland module (systemd.enable = true) is used,
    # it sets NIX_XDG_DESKTOP_PORTAL_DIR which overrides system portals.
    # We must explicitly include all portals we need here.
    # See: https://github.com/nix-community/home-manager/issues/7124
    xdg.portal = {
      extraPortals = with pkgs; [
        xdg-desktop-portal-gnome
        # xdg-desktop-portal-hyprland is automatically added by Hyprland module
      ];
      # Config is set at NixOS level in nixosConfigurations/modules/hyprland.nix
    };
  };
}
