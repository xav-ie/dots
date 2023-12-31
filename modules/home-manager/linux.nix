{
  pkgs,
  pwnvim,
  lib,
  ...
} @ inputs: let
  merge = lib.foldr (a: b: a // b) {};
in {
  home = {
    packages = ( with pkgs; [
        ################################
        # in triage - try to minimize this list
        ################################
        asciinema # record shell sessions and share easily
        age # the new PGP
        blesh # bash extensions
        cliphist
        clipboard-jh # a really awesome clipboard
        ctpv # lf previews, very buggy
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
        pinentry-gnome # I wish I could figure out pinentry-rofi but it does not work
        # prusa-slicer                # does not launch currently
        python312Packages."adblock"
        rofi-rbw # bitwarden cli wrapper
        rbw # unnofficial bitwarden client
        silver-searcher # a better rg? has premade filters
        # slack                       # does not launch currently
        sops # secrets manager? idk... seems like an extension to age and
        # other encrypters that allows you to just encrypt part of the
        # file instead of the whole thing... IDK the real use for that
        tldr # barely working due to it not having many entries
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
        bat # a better cat
        btop # a better top
        delta # a better git diff
        eza # a better ls
        fzf # fuzzy finder
        gh # github cli
        lazygit # easy git tui
        ripgrep # faster grep
        magic-wormhole-rs # send files easily
        neovim # the one and only
        starship # amazing PS1
        thefuck # correct previous command automatically
        zoxide # smart cd
        zellij # tmux could never
        ################################
        # universal utils
        ################################
        cmake
        file # magic number reader
        gcc
        gnumake # provides `make`
        jq # json parser
        lf # file browser
        ninja
        unzip
        unrar
        vim
        wget
        zip
        ################################
        # user programs
        ################################
        bitwarden
        chromium
        discord
        google-chrome
        kitty
        mpv # video player
        networkmanagerapplet
        noisetorch # noise filter
        openrgb # pc rgb control
        pavucontrol # audio mixer
        playerctl # play, pause, next
        pulseaudio # provides pactl for volume control
        qutebrowser
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
                               mesonFlags = oldAttrs.mesonFlags ++ ["-Dexperimental=true"];
                               hyprlandSupport = true;
                               }))

    ] ) ++ [
      inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
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
      LANG = "en_US.UTF-8";
      EDITOR = "nvim";
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
          /* hides the native tabs */
          #TabsToolbar {
            visibility: collapse;
          }
          #titlebar {
            visibility: collapse;
          }
          #sidebar-header {
            visibility: collapse !important;
          }
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
  };

  services = {
    gpg-agent = {
      enable = true;
      pinentryFlavor = "gnome3";
      enableSshSupport = true;
    };
  };

  xdg.mimeApps.defaultApplications = {
    "text/plain" = ["qutebrowser.desktop"];
    "application/pdf" = ["sioyek.desktop"];
    "image/*" = ["sxiv.desktop"];
    "video/*" = ["mpv.desktop"];
    "text/html" = ["qutebrowser.desktop"];
    "x-scheme-handler/http" = ["qutebrowser.desktop"];
    "x-scheme-handler/https" = ["qutebrowser.desktop"];
    "x-scheme-handler/ftp" = ["qutebrowser.desktop"];
    "application/xhtml+xml" = ["qutebrowser.desktop"];
    "application/xml" = ["qutebrowser.desktop"];
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
