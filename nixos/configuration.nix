# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).
{ inputs
, lib
, config
, pkgs
, ...
}: {
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Bootloader
  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    supportedFilesystems = [ "ntfs" ];
    kernelModules = [
      "i2c-dev"
      # Virtual Camera
      "v4l2loopback"
      # Virtual Microphone, built-in
      "snd-aloop"
    ];
    kernelPackages = pkgs.linuxPackages_latest;
    extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback.out ];
    extraModprobeConfig = ''
      # exclusive_caps: Skype, Zoom, Teams etc. will only show device when actually streaming
      # card_label: Name of virtual camera, how it'll show up in Skype, Zoom, Teams
      # https://github.com/umlaeute/v4l2loopback
      options v4l2loopback exclusive_caps=1 card_label="Virtual Camera"
    '';
  };


  networking = {
    hostName = "nixos"; # Define your hostname.
    # Enables wireless support via wpa_supplicant.
    # wireless.enable = true; 
    # nameservers = [ "127.0.0.1" "::1" ];
    nameservers = [ "1.1.1.1" "9.9.9.9" ];
    # nameservers = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];

    # dhcpcd.extraConfig = "nohook resolv.conf";

    # Configure network proxy if necessary
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

    # Enable networking
    networkmanager = {
      enable = true;
      # do not override my dns?
      # dns = "none";
      dns = "systemd-resolved";
    };

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
  users = {
    defaultUserShell = pkgs.zsh;
    users.x = {
      isNormalUser = true;
      description = "x";
      extraGroups = [ "networkmanager" "wheel" "docker" "video" ];
      # packages = with pkgs; [];
      useDefaultShell = true;
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
  # now you don't have to pass --impure when trying to run nix commands
  nixpkgs.config.allowUnfreePredicate = _: true;

  # nixpkgs.overlays = with pkgs; [
  # ];

  environment.systemPackages =
    (with pkgs; [
      nur.repos.dustinblackman.oatmeal
    ]) ;

  # environment.sessionVariables = {
  # };

  # fonts.packages = with pkgs; [
  #   nerdfonts
  # ];
  fonts.fontconfig.enable = true;


  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  programs = {
    hyprland = {
      enable = true;
      xwayland.enable = true;
      package = inputs.hyprland.packages."${pkgs.system}".hyprland;
      # TODO: additional settings should occur in home-manager
    };
    nix-ld.enable = true;
    # must be enabled system-wide in order to be a default shell
    # additional settings should occur in home-manager
    zsh.enable = true;
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
    };
    gnome.gnome-keyring.enable = true;
    openssh = {
      enable = true;
      # since I use zellij, I don't mind disconnecting often and just reconnecting to my session;
      # I want to avoid stale/unresponsive connections
      extraConfig = ''
        ClientAliveInterval 30
        ClientAliveCountMax 3
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
      enable = true;
      dnssec = "true";
      domains = [ "~." ];
      fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
      extraConfig = ''
        DNSOverTLS=yes
      '';
    };

    # twingate.enable = true;
    udev = {
      packages = [ pkgs.openrgb ];
      extraRules = ''
        SUBSYSTEM=="usb", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="3000", MODE="0666"
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7321", MODE="0666"
      '';
    };
    # Configure keymap in X11
    xserver = {
      layout = "us";
      xkbVariant = "";
      videoDrivers = [ "nvidia" ];
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

  virtualisation.docker.enable = true;

  # just don't change this. there is never a good reason to change this as all updates still 
  # apply and changing this just messes things up. it is a state tracker
  system.stateVersion = "23.05"; # Did you read the comment?

  nix = {
    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    # TODO: what does this do??
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    # TODO: Yeah, idk what that means either
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;

    settings = {
      # just run this every once in a while... auto-optimization slows down evaluation
      auto-optimise-store = false;
      experimental-features = [ "nix-command" "flakes" ];
      fallback = true; # allow building from src
      # use max cores/threads when `enableParallelBuilding` is set for package
      cores = 0;
      # use max CPUs for nix build jobs
      max-jobs = "auto";
    };
  };
}
