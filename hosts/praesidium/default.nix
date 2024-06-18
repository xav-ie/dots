{
  config,
  inputs,
  outputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    # TODO: investigate what these actually do
    inputs.hardware.nixosModules.common-cpu-intel-cpu-only
    inputs.hardware.nixosModules.common-gpu-nvidia-nonprime
    inputs.hardware.nixosModules.common-pc-ssd

    ./hardware-configuration.nix

    ../common
    # ../common/global
    # ../common/users/misterio
    # ../common/users/layla

    # ../common/optional/pantheon.nix
    # ../common/optional/quietboot.nix
  ];

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
    initrd = {
      preDeviceCommands = ''
        message="Hello, this is Praesidium."
        printf "$message" | ${pkgs.cowsay}/bin/cowsay -n
      '';
    };
  };

  documentation = {
    dev.enable = true;
    man.generateCaches = true;
    nixos.includeAllModules = true;
  };

  networking = {
    hostName = "praesidium"; # Define your hostname.
    # Enables wireless support via wpa_supplicant.
    # wireless.enable = true; 
    # nameservers = [ "127.0.0.1" "::1" ];
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
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
      extraGroups = [
        "networkmanager"
        "wheel"
        "docker"
        "video"
      ];
      # packages = with pkgs; [];
      useDefaultShell = true;
    };
  };

  nixpkgs = {
    overlays = builtins.attrValues outputs.overlays;
    # Allow unfree packages
    config.allowUnfree = true;
    # now you don't have to pass --impure when trying to run nix commands
    config.allowUnfreePredicate = _: true;
  };

  environment.systemPackages = (
    with pkgs;
    [
      nur.repos.dustinblackman.oatmeal
      # TODO: fix this :/
      # g
      record
      record-section
    ]
  );

  # trying to fix hypr anomalies
  environment.sessionVariables = {
    BROWSER = "firefox";
    EDITOR = "$HOME/Projects/xnixvim/result/bin/nvim";
    LANG = "en_US.UTF-8";
    LC_ALL = "en_US.UTF-8";
    # causes bug if set. dont do it!
    BAT_PAGER = "";
    # PAGER = ''bat -p --pager="moar -quit-if-one-screen" --terminal-width=\$(expr $COLUMNS - 4)'';
    # PAGER = ''bat -p --terminal-width=123 --pager="moar -quit-if-one-screen" '';
    # TODO: figure out the numbers thing
    PAGER = ''bat -p --terminal-width=123 --pager="moar" '';
    MANPAGER = "nvim +Man!";
    # This ensures man-width is not pre-cut before it reaches nvim. Nvim can do that. 
    MANWIDTH = "999";
    MOAR = "-quit-if-one-screen";
    # This makes animations in neovide not have to sync, unlocking faster refresh rates.
    NEOVIDE_VSYNC = "0";
    TERMINAL = "wezterm";
    # get more colors
    HSTR_CONFIG = "hicolor";
    # leading space hides commands from history
    HISTCONTROL = "ignorespace";
    # increase history file size (default is 500)
    HISTFILESIZE = "10000";
    PATH = "$HOME/.config/scripts/:$PATH";
  };

  fonts.fontconfig.enable = true;
  fonts.packages = with pkgs; [
    maple-mono
    maple-mono-NF
    nerdfonts
  ];

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
    # installs a special kernel module to enable tracing
    sysdig.enable = true;
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
      # package = pkgs.nvidia-vaapi-driver; # For NVIDIA
      # extraPackages = with pkgs; [
      # nvidia-vaapi-driver # For NVIDIA
      # This one below would probably be helpful if you had integrated graphics
      # intel-media-driver # LIBVA_DRIVER_NAME=iHD
      # vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
      # vaapiVdpau
      # libvdpau-va-gl
      # ];
    };
    nvidia = {
      modesetting.enable = true;
      # allows systemd to better control nvidia card
      # turns on NVreg_PreserveVideoMemoryAllocations=1
      # it also sets up systemd to properly suspend, hibernate, and resume
      # https://download.nvidia.com/XFree86/Linux-x86_64/515.65.01/README/powermanagement.html
      powerManagement.enable = true;
      # only available if your CPU has integrated graphics
      # I was a doofus and did not buy one with that
      # prime = {
      #   offload = {
      #     enable = true;
      #     enableOffloadCmd = true;
      #   };
      #   # 01:00.0 VGA compatible controller: NVIDIA Corporation GA104 [GeForce RTX 3060 Ti Lite Hash Rate] (rev a1)
      #   nvidiaBusId = "PCI:1:0:0";
      #   # darn it, I will have to remember to buy a cpu with integrated graphics next time :(((((
      #   intelBusId = "???";
      # };
      open = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.production;
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
      fallbackDns = [
        "1.1.1.1#one.one.one.one"
        "1.0.0.1#one.one.one.one"
      ];
      extraConfig = ''
        DNSOverTLS=yes
      '';
    };

    # twingate.enable = true;
    # TODO: fix
    udev = {
      packages = [ pkgs.openrgb ];
      extraRules = ''
        SUBSYSTEM=="usb", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="3000", MODE="0666"
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7321", MODE="0666"
      '';
    };
    # Configure keymap in X11
    xserver = {
      xkb = {
        layout = "us";
        variant = "";
      };
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
    gc = {
      persistent = true; # nixos only
      dates = "weekly"; # nixos only
    };

    # This will add each flake input as a registry
    # To make nix3 commands consistent with your flake
    # TODO: what does this do??
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;

    # This will additionally add your inputs to the system's legacy channels
    # Making legacy nix commands consistent as well, awesome!
    # TODO: Yeah, idk what that means either
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.to.path}") config.nix.registry;
  };

  systemd = {
    # must be system service due to journalctl needing elevated permissions
    services.clear-log = {
      description = "Clear >1 month-old logs every week";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/journalctl --vacuum-time=21d";
      };
    };
    timers.clear-log = {
      wantedBy = [ "timers.target" ];
      partOf = [ "clear-log.service" ];
      timerConfig.OnCalendar = "weekly UTC";
    };
  };
  # boot = {
  #   kernelPackages = pkgs.linuxKernel.packages.linux_zen;
  #   binfmt.emulatedSystems = [
  #     "aarch64-linux"
  #     "i686-linux"
  #   ];
  # };
  #
  # boot.kernelModules = [ "coretemp" ];
  # services.thermald.enable = true;
  # environment.etc."sysconfig/lm_sensors".text = ''
  #   HWMON_MODULES="coretemp"
  # '';
}
