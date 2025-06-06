{ pkgs, ... }:
{
  imports = [
    ../programs/firefox
    ../programs/obs
    ../programs/sioyek
    ../programs/swaynotificationcenter
    ../programs/waybar
    ./hyprland.nix
    ./systemd.nix
  ];

  config = {
    home = {
      packages =
        (with pkgs; [
          # TODO: remove
          dconf
          ################################
          # in triage - try to minimize this list
          ################################
          asciinema # record shell sessions and share easily
          age # the new PGP
          cliphist
          clipboard-jh # a really awesome clipboard
          ghostty
          manix
          # nodePackages."webtorrent-cli"
          xidel # like jq but for html and much more advanced.
          # I wish I could figure out pinentry-rofi but it does not work
          pinentry-gnome3
          # prusa-slicer                # does not launch currently
          python312Packages."adblock"
          rofi-rbw # bitwarden cli wrapper
          xdg-utils # xdg-open, xdg-mime, xdg-email, etc.
          wf-recorder
          # wtype # xdotool for wayland; used as part of rofi-rbw for typing
          yt-dlp # better yt-dl
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
          bitwarden
          chromium
          # discord
          # TODO: move into hm services
          networkmanagerapplet
          noisetorch # noise filter
          pavucontrol # audio mixer
          # TODO: move into hm services
          playerctl # play, pause, next
          pulseaudio # provides pactl for volume control
          # qutebrowser
        ])
        ++ (with pkgs.pkgs-bleeding; [
          # needs latest security releases
          signal-desktop
        ])
        ++ (with pkgs.pkgs-mine; [
          move-active
          record
          record-section
        ]);

      # The state version is required and should stay at the version you
      # originally installed.
      stateVersion = "23.11";
      sessionVariables = {
        # va-api driver to use 'nvidia', '', ...
        LIBVA_DRIVER_NAME = "nvidia";
        GBM_BACKEND = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        XDG_CONFIG_HOME = "/home/x/.config";
        NIXOS_OZONE_WL = "1";
        WLR_NO_HARDWARE_CURSORS = "1";
      };
    };
    programs = {
      rbw.enable = true; # unnofficial bitwarden client
      lazygit.enable = true; # easy git tui
      himalaya.enable = true; # email
    };

    services = {
      gpg-agent = {
        enable = true;
        pinentry.package = pkgs.pinentry-gnome3;
        enableSshSupport = true;
      };
    };

    dconf.settings = {
      # tell gtk applications to prefer dark mode, please!
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
      };
    };

    gtk = {
      enable = true;
      font = {
        name = "Inter";
        package = pkgs.inter;
        size = 14;
      };
      iconTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };
      theme = {
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };
    };

    # TODO: somehow make mac support this
    xdg.mimeApps.enable = true;
    # TODO: can global xdg.portal config be moved here?
    # I need the flatpak option, too, I think
  };
}
