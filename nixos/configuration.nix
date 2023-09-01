# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ inputs, lib, config, pkgs, fetchFromGithub, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];
  
  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];
  boot.kernelModules = [ 
    "i2c-dev"
    # Virtual Camera
    "v4l2loopback"
    # Virtual Microphone, built-in
    "snd-aloop"
    ];
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.extraModulePackages = with config.boot.kernelPackages;
    [ v4l2loopback.out ];
  boot.extraModprobeConfig = ''
    # exclusive_caps: Skype, Zoom, Teams etc. will only show device when actually streaming
    # card_label: Name of virtual camera, how it'll show up in Skype, Zoom, Teams
    # https://github.com/umlaeute/v4l2loopback
    options v4l2loopback exclusive_caps=1 card_label="Virtual Camera"
  '';

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.



  networking.nameservers = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
  
  services.resolved = {
    enable = true;
    dnssec = "true";
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
    extraConfig = ''
      DNSOverTLS=yes
    '';
  };
  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;


  # Set your time zone.
  time.timeZone = "America/Phoenix";

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

  # Configure keymap in X11
  services.xserver = {
    layout = "us";
    xkbVariant = "";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.x = {
    isNormalUser = true;
    description = "x";
    extraGroups = [ "networkmanager" "wheel" "docker" "video" ];
    packages = with pkgs; [];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  
  nixpkgs.overlays = with pkgs; [
    (self: super: {
      mpv-unwrapped = super.mpv-unwrapped.override {
        ffmpeg_5 = ffmpeg_5-full;
      };
    })
  ];

  environment.systemPackages = (with pkgs; [
    bat
	  blesh
    cava
    chromium
    cliphist
    ctpv # lf previews
    cudaPackages.cudatoolkit
    cudaPackages.cudnn
    cudaPackages.cuda_cccl
    discord
    # dunst
    exa
    file
    fzf
    gcc
    gh
    google-chrome
  	gnumake
    hstr
    htop
    killall
    kitty
    lazygit
    lf
    libnotify
    manix	
    magic-wormhole-rs
    mpv
    mpvpaper
    networkmanagerapplet
    neovim
    noisetorch
    openrgb
    pavucontrol
    pciutils
    pistol
    polkit_gnome
    prusa-slicer
    ripgrep
    rofi-wayland
    slack
    sioyek
    starship
    swaynotificationcenter
    swayidle
    swaylock
    swww
    tldr
    tmux
    thefuck
    unzip
    vim 
    (waybar.overrideAttrs (oldAttrs: {
      mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
      hyprlandSupport = true;
    }))
    waypipe
    wget
    wl-clipboard
    xdg-utils
    zip
    zoxide
  ]) ++ [
      inputs.hyprland-contrib.packages.${pkgs.system}.grimblast # or any other package
  ];

  security.wrappers.noisetorch = {
    owner = "root";
    group = "root";
    source = "${pkgs.noisetorch}/bin/noisetorch";
    capabilities = "cap_sys_resource+ep";
  };

  fonts.packages = with pkgs; [
    nerdfonts
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

  xdg.portal.enable = true;

  programs = {
    hyprland = {
      enable = true;
      enableNvidiaPatches = true;
      xwayland.enable = true;
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
    };
    nvidia = {
      modesetting.enable = true;
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
    };
  };
  
  # services.twingate.enable = true;
  
  services.blueman.enable = true;
  
  services.xserver.videoDrivers = [ "nvidia" ];

  sound.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  security.polkit.enable = true;
  security.pam.services.swaylock.text = ''
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


  # TODO: get this working
  systemd = {
    user.services.polkit-gnome-authentication-agent-1 = {
      description = "polkit-gnome-authentication-agent-1";
      # wantedBy = [ "graphical-session.target" ];
      # wants = [ "graphical-session.target" ];
      # after = [ "graphical-session.target" ];
      wantedBy = [ "default.target" ];
      after = [ "default.target" ];
      serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;
        };
    };
  };
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:
  services.udev.packages = [ pkgs.openrgb ];

  # virtualisation.docker.enable = true;
  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

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
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      auto-optimise-store = true;
      experimental-features = [ "nix-command" "flakes" ];
      fallback = true; # allow building from src
      # use max cores when `enableParallelBuilding` is set for package 
      cores = 0;
      # use max CPUs for nix build jobs... not entirely sure if this is that 
      # different from `cores` option
      max-jobs = "auto";
    };

  };
}
