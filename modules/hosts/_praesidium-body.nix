# praesidium (desktop tower) host-specific configuration.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = {
    nixpkgs.config = {
      cudaSupport = true;
      cudaCapabilities = [ "8.6" ];
      cudaForwardCompat = true;
    };

    boot = {
      # binfmt.emulatedSystems = [
      #   "aarch64-linux"
      #   "i686-linux"
      # ];
      loader.systemd-boot.enable = true;
      loader.efi.canTouchEfiVariables = true;
      supportedFilesystems = [ "ntfs" ];
      tmp.cleanOnBoot = true;
      # https://wiki.archlinux.org/title/NVIDIA
      kernelParams = [
        # creates nvidia framebuffer device at boot; it takes over simpledrm at
        # boot
        "nvidia-drm.fbdev=1"
        # Reduce kernel boot chatter so it doesn't paint over greetd on TTY1.
        # Logs still go to the journal — see them with `journalctl -kb`.
        "quiet"
      ];
      # Print warnings and worse (priority < 5: emerg/alert/crit/err/warn) to
      # the console at runtime; notice/info/debug remain in the journal only.
      # See them with `journalctl -kb`.
      consoleLogLevel = 5;
      kernelModules = [
        # Virtual Camera
        "v4l2loopback"
      ];
      kernelPackages = pkgs.pkgs-bleeding.linuxPackages_latest;
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

    # TODO: investigate why slow
    # documentation = {
    #   dev.enable = true;
    #   man.generateCaches = true;
    #   nixos.includeAllModules = true;
    # };

    networking = {
      hostName = "praesidium"; # Define your hostname.
      # Enables wireless support via wpa_supplicant.
      # wireless.enable = true;
      # use services.dnsmasq
      nameservers = [ "127.0.0.1" ];
      # nameservers =
      #   let
      #     ips = [
      #       "1.1.1.1"
      #       "1.0.0.1"
      #       "2606:4700:4700::1111"
      #       "2606:4700:4700::1001"
      #     ];
      #     sni = "one.one.one.one";
      #   in
      #   map (ip: "${ip}#${sni}") ips;

      # dhcpcd.extraConfig = "nohook resolv.conf";

      # Configure network proxy if necessary
      # proxy.default = "http://user:password@proxy:port/";
      # proxy.noProxy = "127.0.0.1,localhost,internal.domain";

      # Enable networking
      networkmanager = {
        enable = true;
        # rely on dnsmasq service
        dns = "none";
        # Stop NM from trying to set sysctls on Wi-Fi Direct virtual devices —
        # the kernel doesn't expose IPv4 forwarding for them, so NM logs an
        # EINVAL warning every boot.
        # Tailscale and ProtonVPN manage their own routes and policy
        # tables; let NM stay out of their way. p2p-dev-* are the
        # Wi-Fi Direct virtual devices the kernel doesn't expose
        # IPv4 forwarding for.
        unmanaged = [
          "interface-name:p2p-dev-*"
          "interface-name:tailscale*"
          "interface-name:proton-*"
          "interface-name:ipv6leakintrf*"
        ];
      };

      # Open ports in the firewall.
      # firewall.allowedTCPPorts = [ ... ];
      # firewall.allowedUDPPorts = [ ... ];
      # Or, disable the firewall altogether.
      firewall.enable = false;
    };

    # Set your time zone.
    time.timeZone = "America/New_York";

    # Select internationalisation properties.
    i18n =
      let
        language = "en_US.UTF-8";
      in
      {
        defaultLocale = language;
        extraLocaleSettings = {
          LANG = language;
          LC_ADDRESS = language;
          LC_IDENTIFICATION = language;
          LC_MEASUREMENT = language;
          LC_MONETARY = language;
          LC_NAME = language;
          LC_PAPER = language;
          LC_TELEPHONE = language;
          # DNE
          # LC_ALL = language;
          # LC_NUMERIC = language;
          # LC_TIME = language;
          # TODO: better way to do this?
        };
      };

    # Define a user account. Don't forget to set a password with ‘passwd’.
    users = {
      defaultUserShell = pkgs.zsh;
      users."${config.defaultUser}" = {
        isNormalUser = true;
        description = config.defaultUser;
        extraGroups = [
          "docker"
          "input"
          "networkmanager"
          "video"
          "wheel"
          "ydotool"
        ];
        # packages = with pkgs; [];
        useDefaultShell = true;
      };
    };

    environment.systemPackages = with pkgs; [
      wakeonlan # For waking nox (macOS remote builder) over LAN
    ];

    environment.sessionVariables = { };

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    # programs.mtr.enable = true;
    # programs.gnupg.agent = {
    #   enable = true;
    #   enableSSHSupport = true;
    # };

    programs = {
      ydotool.enable = true;
      # installs a special kernel module to enable tracing
      sysdig.enable = true;
      # must be enabled system-wide in order to be a default shell
      # additional settings should occur in home-manager
      zsh.enable = true;
    };

    hardware = {
      enableAllFirmware = true;
      graphics = {
        enable = true;
        enable32Bit = true;
        package = pkgs.nvidia-vaapi-driver; # For NVIDIA
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
        #   # 01:00.0 VGA compatible controller: NVIDIA Corporation GA104
        #   # [GeForce RTX 3060 Ti Lite Hash Rate] (rev a1)
        #   nvidiaBusId = "PCI:1:0:0";
        #   # darn it, I will have to remember to buy a cpu with integrated
        #   # graphics next time (;´༎ຶД༎ຶ`)
        #   intelBusId = "N/A";
        # };
        open = false;
        nvidiaSettings = true;
        # beta, production, stable (=production), or latest (=MAX(production,
        # some version))
        package = config.boot.kernelPackages.nvidiaPackages.beta;
        # forceFullCompositionPipeline = true;
      };
      nvidia-container-toolkit.enable = true;
    };

    services = {
      orca.enable = true;
      flatpak.enable = true;
      geoclue2.enable = true;
      plover.enable = true;
      virtual-headset = {
        enable = true;
        user = config.defaultUser;
      };

      resolved = {
        enable = false;
        # dnssec = "true";
        # dnsovertls = "true";
        # domains = [ "~." ];
        # # dns => defaults to config.networking.nameservers
        # fallbackDns =
        #   let
        #     ips = [
        #       "9.9.9.9"
        #       "149.112.112.112"
        #       "2620:fe::fe"
        #       "2620:fe::9"
        #     ];
        #     sni = "dns.quad9.net";
        #   in
        #   map (ip: "${ip}#${sni}") ips;
        extraConfig = ''
          DNSStubListener=no
        '';
      };
      # udev = {
      #   # TODO: for `ns-usbloader`
      #   extraRules = # python
      #     ''
      #       SUBSYSTEM=="usb", ATTRS{idVendor}=="057e", ATTRS{idProduct}=="3000", MODE="0666"
      #       SUBSYSTEM=="usb", ATTRS{idVendor}=="0955", ATTRS{idProduct}=="7321", MODE="0666"
      #     '';
      # };
      # Configure keymap in X11
      xserver = {
        xkb.layout = "us";
        xkb.variant = "";
        videoDrivers = [ "nvidia" ];
      };

      # Host values for this machine's single-GPU workloads; definitions live in
      # nixos/{nginx,llama-server}.nix.
      reverse-proxy.enable = false;

      # llama.cpp server for local AI code completion (cursortab).
      # Accessible at https://llama.lalala.casa via traefik. Sweep ships
      # only as GGUF, which llama.cpp loads natively (vLLM cannot).
      # Disabled: cursortab now uses Featherless.ai's hosted sweep-next-edit-v2-7B
      # ($10/mo, no local GPU). Flip to `true` + repoint cursortab to self-host.
      llama-server = {
        enable = false;
        model = "sweepai/sweep-next-edit-1.5B";
        contextSize = 8192;
        flashAttention = "on";
        cacheReuse = 256;
        kvCacheType = "q8_0";
        speculation = {
          enable = true;
          type = "ngram-simple";
        };
      };
    };

    location = {
      longitude = 40.0;
      latitude = 90.0;
    };

    # Ensure proper suspend-to-RAM (keeps RAM powered, fast resume)
    systemd.sleep.extraConfig = ''
      AllowSuspend=yes
      AllowHibernation=no
      AllowSuspendThenHibernate=no
      AllowHybridSleep=no
      SuspendState=mem
    '';

    # NetworkManager-wait-online blocks boot unnecessarily - network services
    # already have proper After=network-online.target dependencies
    systemd.services.NetworkManager-wait-online.wantedBy = lib.mkForce [ ];

    # Just don't change this. There is never a good reason to change this as all updates still
    # apply and changing this just messes things up. It is a state tracker
    system.stateVersion = "23.05"; # Did you read the comment?

    nix = {
      gc = {
        persistent = true; # nixos only
        dates = "weekly"; # nixos only
      };
    };
  };
}
