{ pkgs
, lib
, inputs
, ...
}:
let
  merge = lib.foldr (a: b: a // b) { };
in
{
  home = {
    packages = (with pkgs; [
      ################################
      # in triage - try to minimize this list
      ################################
      microsoft-edge
      slack
      asciinema # record shell sessions and share easily
      age # the new PGP
      blesh # bash extensions
      cliphist
      clipboard-jh # a really awesome clipboard
      # cudaPackages.cuda_cccl # I wish hardware acceleration would work :/
      # cudaPackages.cudatoolkit
      # cudaPackages.cudnn
      himalaya # email
      hstr
      manix
      nodePackages."webtorrent-cli"
      xidel # like jq but for html and much more advanced.
      # required by mpvScripts.webtorrent-mpv-hook
      pciutils
      pinentry-gnome3 # I wish I could figure out pinentry-rofi but it does not work
      # prusa-slicer                # does not launch currently
      python312Packages."adblock"
      rofi-rbw # bitwarden cli wrapper
      rbw # unnofficial bitwarden client
      # slack                       # does not launch currently
      sops # secrets manager? idk... seems like an extension to age and
      # other encrypters that allows you to just encrypt part of the
      # file instead of the whole thing... IDK the real use for #that
      # tldr # barely working due to it not having many entries
      xdg-utils # ????
      weechat
      wtype # xdotool for wayland; used as part of rofi-rbw for typing
      # passwords out
      yt-dlp # better yt-dl
      zoom-us
      # https://github.com/marionebl/svg-term-cli
      # allows asciinema recordings to be exported to svg... this could be pretty indespensable if
      # you would like ANSI escape sequences to be interpreted by GH
      ################################
      # awesome dev tools
      ################################
      lazygit # easy git tui
      #neovim # the one and only
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
      google-chrome
      mpv # video player
      networkmanagerapplet
      noisetorch # noise filter
      openrgb # pc rgb control
      pavucontrol # audio mixer
      nerdfonts
      # (pkgs.nerdfonts.override { fonts = [ "Meslo" ]; })
      playerctl # play, pause, next
      pulseaudio # provides pactl for volume control
      # qutebrowser
      sioyek # vimified pdf viewer
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
      swaynotificationcenter
      swww
      waypipe
      wl-clipboard
      (waybar.overrideAttrs (oldAttrs: {
        mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
        hyprlandSupport = true;
      }))

    ]) ++ [
      inputs.hyprland-contrib.packages."x86_64-linux".grimblast
    ]
    ;
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
    firefox = {
      enable = true;
      profiles.x = {
        id = 0;
        isDefault = true;
        settings = merge [
          (import ./programs/firefox/annoyances.nix)
          (import ./programs/firefox/settings.nix)
        ];
        userChrome = ''
          /* ########  Sidetabs Styles  ######### */

          /* ~~~~~~~~ Autohiding styles ~~~~~~~~~ */
          :root {
           --sidebar-hover-width: 36px;
           --sidebar-visible-width: 190px;
           --sidebar-debounce-delay: 50ms;
 
          }
          #sidebar-box {
           display: grid !important;
           min-width: var(--sidebar-hover-width) !important;
           max-width: var(--sidebar-hover-width) !important;
           overflow: visible !important;
           height: 100% !important;
           min-height: 100% !important;
           max-height: 100% !important;
          }
          #sidebar {
           height: 100% !important;
           width: var(--sidebar-hover-width) !important;
           z-index: 200 !important;
           position: absolute !important;
           transition: width 150ms var(--sidebar-debounce-delay) ease !important;
           min-width: 0 !important;
          }
          #sidebar:hover {
           width: var(--sidebar-visible-width) !important;
          }
          /* ~~~~~~~~ Hidden elements styles ~~~~~~~~~ */
          #TabsToolbar {
          	display: none !important;
          }
          #titlebar {
          	display: none !important;
          }
          #sidebar-header {
          	display: none !important;
          }
          /* ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ */

          /* #################################### */
        '';
        extensions = with pkgs.nur.repos.rycee.firefox-addons; [
          bitwarden
          ublock-origin
          vimium-c
          sidebartabs
          newtab-adapter
          videospeed
        ];
      };
    };
    wezterm = {
      # guess this does not work with the flake version
      enableZshIntegration = false;
      # enable flake version because it is more up to date
      package = inputs.wezterm.outputs.packages.${pkgs.system}.default;
    };
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
      Unit = { Description = "Stop spyware after working hours"; };
      Timer = {
        Unit = "kill-spyware.service";
        OnCalendar = "18:00";
        Persistent = true;
      };
      Install = { WantedBy = [ "timers.target" ]; };
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
      Unit = { Description = "Start work programs every weekday at 9am"; };
      Timer = {
        Unit = "start-work.service";
        OnCalendar = "Mon..Fri 09:00";
        Persistent = true;
      };
      Install = { WantedBy = [ "timers.target" ]; };
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
