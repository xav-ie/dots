# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{
  inputs,
  lib,
  config,
  pkgs,
  fetchFromGithub,
  ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = ["ntfs"];
    kernelModules = [
      "i2c-dev"
      # Virtual Camera
      "v4l2loopback"
      # Virtual Microphone, built-in
      "snd-aloop"
    ];
    kernelPackages = pkgs.linuxPackages_latest;
    extraModulePackages = with config.boot.kernelPackages; [v4l2loopback.out];
    extraModprobeConfig = ''
      # exclusive_caps: Skype, Zoom, Teams etc. will only show device when actually streaming
      # card_label: Name of virtual camera, how it'll show up in Skype, Zoom, Teams
      # https://github.com/umlaeute/v4l2loopback
      options v4l2loopback exclusive_caps=1 card_label="Virtual Camera"
    '';
  };

  networking = {
    hostName = "nixos"; # Define your hostname.
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    nameservers = ["1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one"];

    # Configure network proxy if necessary
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

    # Enable networking
    networkmanager.enable = true;

    # Open ports in the firewall.
    # firewall.allowedTCPPorts = [ ... ];
    # firewall.allowedUDPPorts = [ ... ];
    # Or disable the firewall altogether.
    firewall.enable = false;
  };

  # Set your time zone.
  time.timeZone = "America/New_York";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.x = {
    isNormalUser = true;
    description = "x";
    extraGroups = ["networkmanager" "wheel" "docker" "video"];
    packages = with pkgs; [];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  # now you don't have to pass --impure when trying to run nix commands
  nixpkgs.config.allowUnfreePredicate = _: true;

  nixpkgs.overlays = with pkgs; [
    (self: super: {
      mpv = super.mpv.override {
        scripts = with self.mpvScripts; [
          autoload # autoloads entries before and after current entry
          mpris # extends mpv to be controllable with MPD
          mpv-playlistmanager # resolves url titles, SHIFT+ENTER for playlist
          quality-menu # control video quality on the fly
          webtorrent-mpv-hook # extends mpv to handle magnet URLs
        ];
      };
      # use full ffmpeg version to support all video formats
      # mpv-unwrapped = super.mpv-unwrapped.override {
        # ffmpeg_5 = ffmpeg_5-full;
      # };
      weechat = super.weechat.override {
        configure = {availablePlugins, ...}: {
          scripts = with super.weechatScripts; [
            # Idk how to use this one yet
            edit # edit messages in $EDITOR
            wee-slack # slack in weechat
            # I think weeslack already has way to facilitate notifications
            # weechat-notify-send # highlight and notify bindings to notify-send
            weechat-go # command pallette jumping
          ];
        };
      };
      # (final: prev: {
      zjstatus = inputs.zjstatus.packages.${super.system}.default;
      # })
    })
  ];

  environment.systemPackages =
    (with pkgs; [
      ################################
      # in triage - try to minimize this list
      ################################
      asciinema # record shell sessions and share easily
      age # the new PGP
      blesh # bash extensions
      cliphist
      clipboard-jh # a really awesome clipboard
      ctpv # lf previews, very buggy
      cudaPackages.cuda_cccl # I wish hardware acceleration would work :/
      cudaPackages.cudatoolkit
      cudaPackages.cudnn
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
    ])
    ++ [
      inputs.hyprland-contrib.packages.${pkgs.system}.grimblast
    ];

  environment.sessionVariables = {
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

  fonts.packages = with pkgs; [
    nerdfonts
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  # my hunch is that these should be moved to home manager
  programs = {
    gnupg.agent = {
      enable = true;
      pinentryFlavor = "gnome3";
      enableSSHSupport = true;
    };
    hyprland = {
      enable = true;
      #enableNvidiaPatches = true;
      xwayland.enable = true;
      portalPackage = pkgs.xdg-desktop-portal-hyprland.overrideAttrs (oldAttrs: {
        # 1.2.2 has key fixes for nvidia cards for newest hyprland.. but hyprland still borked
        # 1.2.3 has some bugfixes
        version = "1.2.3";

        src = pkgs.fetchFromGitHub {
          owner = "hyprwm";
          repo = "xdg-desktop-portal-hyprland";
          rev = "v1.2.3";
          hash = "sha256-y8q4XUwx+gVK7i2eLjfR32lVo7TYvEslyzrmzYEaPZU=";
        };
      });
      # sets this option for us
      # xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    };
    # firejail = {
    #   enable = true;
    #   wrappedBinaries = {
    #     google-chrome-stable = {
    #       executable = "${pkgs.google-chrome}/bin/google-chrome-stable";
    #       profile = "${pkgs.firejail}/etc/firejail/google-chrome.profile";
    #       desktop = "${pkgs.google-chrome}/share/applications/google-chrome.desktop";
    #     };
    #     librewolf = {
    #       executable = "${pkgs.librewolf}/bin/librewolf";
    #       profile = "${pkgs.firejail}/etc/firejail/librewolf.profile";
    #       extraArgs = [
    #         # Required for U2F USB stick
    #         "--ignore=private-dev"
    #         # Enforce dark mode
    #         "--env=GTK_THEME=Adwaita:dark"
    #         # Enable system notifications
    #         "--dbus-user.talk=org.freedesktop.Notifications"
    #       ];
    #     };
    #   };
    # };
  };

  hardware = {
    enableAllFirmware = true;
    bluetooth.enable = true;
    opengl = {
      enable = true;
      driSupport = true;
      driSupport32Bit = true;
      package = pkgs.nvidia-vaapi-driver; # For NVIDIA
      extraPackages = with pkgs; [
        nvidia-vaapi-driver # For NVIDIA
        intel-media-driver # LIBVA_DRIVER_NAME=iHD
        vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
        # vaapiVdpau
        # libvdpau-va-gl
      ];
    };
    nvidia = {
      modesetting.enable = true;
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };
  };

  services = {
    blueman.enable = true;
    flatpak.enable = true;
    geoclue2 = {
      enable = true;
      appConfig.redshift.isAllowed = true;
    };
    gnome.gnome-keyring.enable = true;
    openssh = {
      enable = true;
      extraConfig = ''
        ClientAliveInterval 60
        ClientAliveCountMax 5
      '';
    };
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      jack.enable = true;
    };
    redshift = {
      enable = true;
    };
    resolved = {
      enable = lib.mkForce true;
      dnssec = "true";
      domains = ["~."];
      fallbackDns = ["1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one"];
      extraConfig = ''
        DNSOverTLS=yes
      '';
    };
    twingate.enable = true;
    udev = {
      packages = [pkgs.openrgb];
      extraRules = ''
        SUBSYSTEM=="usb", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="3000", MODE="0666"
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7321", MODE="0666"
      '';
    };
    # Configure keymap in X11
    xserver = {
      layout = "us";
      xkbVariant = "";
      videoDrivers = ["nvidia"];
    };
  };

  # location.provider = "geoclue2";
  location = {
    longitude = 40.0;
    latitude = 90.0;
  };

  security = {
    pam.services.swaylock.text = ''
      # Account management.
      account required pam_unix.so

      # Authentication management.
      auth sufficient pam_unix.so   likeauth try_first_pass
      auth required pam_deny.so

      # Password management.
      password sufficient pam_unix.so nullok sha512

      # Session management.
      session required pam_env.so conffile=/etc/pam/environment readenv=0
      session required pam_unix.so
    '';
    polkit.enable = true;
    rtkit.enable = true;
    wrappers.noisetorch = {
      owner = "root";
      group = "root";
      source = "${pkgs.noisetorch}/bin/noisetorch";
      capabilities = "cap_sys_resource+ep";
    };
  };

  sound.enable = true;

  systemd = {
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      # wantedBy = [ "graphical-session.target" ];
      # wants = [ "graphical-session.target" ];
      # after = [ "graphical-session.target" ];
      wantedBy = ["default.target"];
      after = ["default.target"];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 1;
        TimeoutStopSec = 10;
      };
    };
  };

  virtualisation.docker.enable = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    registry = lib.mapAttrs (_: value: {flake = value;}) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      auto-optimise-store = true;
      experimental-features = ["nix-command" "flakes"];
      fallback = true; # allow building from src
      # use max cores when `enableParallelBuilding` is set for package
      cores = 0;
      # use max CPUs for nix build jobs... not entirely sure if this is that
      # different from `cores` option
      max-jobs = "auto";
    };
  };
}
