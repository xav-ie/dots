{ pkgs, inputs, ... }:
{
  imports = [
    ./programs/firefox
    ./programs/swaynotificationcenter
    ./programs/waybar
  ];
  home = {
    packages =
      (with pkgs; [
        ################################
        # in triage - try to minimize this list
        ################################
        asciinema # record shell sessions and share easily
        age # the new PGP
        cliphist
        clipboard-jh # a really awesome clipboard
        manix
        nodePackages."webtorrent-cli"
        xidel # like jq but for html and much more advanced.
        # required by mpvScripts.webtorrent-mpv-hook
        pciutils
        pinentry-gnome3 # I wish I could figure out pinentry-rofi but it does not work
        # prusa-slicer                # does not launch currently
        python312Packages."adblock"
        rofi-rbw # bitwarden cli wrapper
        slack
        sops
        xdg-utils # xdg-open, xdg-mime, xdg-email, etc.
        wf-recorder
        # wtype # xdotool for wayland; used as part of rofi-rbw for typing
        yt-dlp # better yt-dl
        zoom-us
        # https://github.com/marionebl/svg-term-cli
        # allows asciinema recordings to be exported to svg... this could be pretty indespensable if
        # you would like ANSI escape sequences to be interpreted by GH
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
        discord
        # TODO: move into hm services
        networkmanagerapplet
        noisetorch # noise filter
        openrgb # pc rgb control
        pavucontrol # audio mixer
        # TODO: move into hm services
        playerctl # play, pause, next
        pulseaudio # provides pactl for volume control
        # qutebrowser
        ################################
        # hyprland
        ################################
        cava
        libnotify
        libva
        libva-utils # hardware video acceleration
        polkit_gnome # just a GUI askpass
        rofi-wayland
        swayidle
        swaylock
        swww
        waypipe
        wl-clipboard
      ])
      ++ [ inputs.hyprland-contrib.packages."x86_64-linux".grimblast ];
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
    sioyek.enable = true; # vimified pdf viewer
    # idk what's happening. It has not been working for awhile
    # wezterm = {
    #   # guess this does not work with the flake version
    #   enableZshIntegration = false;
    #   # enable flake version because it is more up to date
    #   package = inputs.wezterm.outputs.packages.${pkgs.system}.default;
    # };
  };

  services = {
    gpg-agent = {
      enable = true;
      pinentryPackage = pkgs.pinentry-gnome3;
      enableSshSupport = true;
    };
  };

  systemd.user = {
    services.ollama-server = {
      Unit = {
        Description = "Run ollama server";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
      Service = {
        ExecStart = "${pkgs.ollama}/bin/ollama serve";
      };
    };

    # Zoom and Slack love to "helpfully" stay open even when I kill them through UI
    services.kill-spyware = {
      Unit = {
        Description = "Stop spyware";
      };
      Service = {
        Type = "oneshot";
        ExecStart = ./dotfiles/kill-spyware.sh;
        # I guess you need this? :/
        Environment = "PATH=/run/current-system/sw/bin";
      };
    };
    timers.kill-spyware = {
      Unit = {
        Description = "Stop spyware after working hours";
      };
      Timer = {
        Unit = "kill-spyware.service";
        OnCalendar = "18:00";
        Persistent = true;
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };

    services.start-work = {
      Unit = {
        Description = "Start work programs";
      };
      Service = {
        Type = "oneshot";
        ExecStart = ./dotfiles/start-work.sh;
        Environment = "PATH=/run/current-system/sw/bin";
      };
    };
    timers.start-work = {
      Unit = {
        Description = "Start work programs every weekday at 9am";
      };
      Timer = {
        Unit = "start-work.service";
        OnCalendar = "Mon..Fri 09:00";
        Persistent = true;
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };

  xdg.mimeApps.defaultApplications = {
    "text/plain" = [ "firefox.desktop" ];
    "application/pdf" = [ "sioyek.desktop" ];
    "image/*" = [ "firefox.desktop" ];
    "video/*" = [ "mpv.desktop" ];
    "text/html" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
    "x-scheme-handler/ftp" = [ "firefox.desktop" ];
    "application/xhtml+xml" = [ "firefox.desktop" ];
    "application/xml" = [ "firefox.desktop" ];
  };
  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  gtk = {
    enable = true;
    theme.name = "adw-gtk3";
    cursorTheme.name = "Bibata-Modern-Ice";
    iconTheme.name = "GruvboxPlus";
  };
}
