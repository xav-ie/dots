{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  fontCfg = config.fonts.fontconfig;
  inherit ((import ../../../lib/fonts.nix { inherit lib pkgs; })) fonts;
in
{
  imports = [
    inputs.hardware.nixosModules.common-cpu-intel-cpu-only
    inputs.hardware.nixosModules.common-gpu-nvidia-nonprime
    inputs.hardware.nixosModules.common-pc-ssd
    ../../modules
  ];

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
      # https://wiki.archlinux.org/title/NVIDIA
      kernelParams = [
        # creates nvidia framebuffer device at boot; it takes over simpledrm at
        # boot
        "nvidia-drm.fbdev=1"
      ];
      kernelModules = [
        # Virtual Camera
        "v4l2loopback"
        # Virtual Microphone, built-in
        "snd-aloop"
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
          printf "$message" | ${lib.getExe pkgs.cowsay} -n
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
        ];
        # packages = with pkgs; [];
        useDefaultShell = true;
      };
    };

    # environment.etc."sysconfig/lm_sensors".text = ''
    #   HWMON_MODULES="coretemp"
    # '';

    environment.systemPackages = with pkgs; [
      nur.repos.dustinblackman.oatmeal
    ];

    environment.sessionVariables = { };

    fonts = {
      inherit (fonts) packages;
      fontconfig = {
        enable = true;

        localConf = # xml
          ''
            <?xml version="1.0"?>
            <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:font.dtd">
            <fontconfig>
              <match target="font">
                <description>Enable some typographic features of Maple Mono NF font, for all applications.</description>
                <test name="family" compare="eq" ignore-blanks="true">
                  <string>${fonts.name "mono"}</string>
                </test>
                <edit name="fontfeatures" mode="append">
                ${lib.concatStringsSep "\n    " (
                  map (feature: "  <string>${feature} on</string>") (fonts.features "mono")
                )}
                </edit>
              </match>
              <alias>
                <description>Some websites do not respect lacking Arial, use font-sans as fallback</description>
                <family>Arial</family>
                <prefer>
                ${lib.concatStringsSep "\n    " (
                  map (font: "  <family>${font}</family>") fontCfg.defaultFonts.sansSerif
                )}
                </prefer>
              </alias>
              <alias>
                <description>Some websites do not respect sans-serif and demand a ui-sans-serif</description>
                <family>ui-sans-serif</family>
                <prefer>
                ${lib.concatStringsSep "\n    " (
                  map (font: "  <family>${font}</family>") fontCfg.defaultFonts.sansSerif
                )}
                </prefer>
              </alias>
            </fontconfig>
          '';

        defaultFonts = {
          serif = [
            (fonts.name "serif")
            (fonts.name "emoji")
          ];
          sansSerif = [
            (fonts.name "sans")
            (fonts.name "emoji")
          ];
          monospace = [
            (fonts.name "mono")
          ];
          emoji = [ (fonts.name "emoji") ];
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

    programs = {
      nh = {
        enable = true;
        clean.enable = true;
        clean.extraArgs = "--keep-since 7d --keep 20";
        flake = "/home/${config.defaultUser}/Projects/dots";
      };
      nix-ld = {
        enable = true;
        package = pkgs.nix-ld-rs;
        # TODO: minimize and split per-program
        libraries = with pkgs; [
          alsa-lib
          atk
          at-spi2-atk
          at-spi2-core
          cairo
          cups
          curl
          dbus
          enchant
          expat
          flite
          fontconfig
          fontconfig.lib
          freetype
          fuse3
          gdk-pixbuf
          # TODO: do I need all three?
          glib
          glibc
          glib.out
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-base
          gst_all_1.gstreamer
          gtk3
          harfbuzz
          harfbuzzFull
          hyphen
          icu
          icu66
          json-glib
          lcms
          libappindicator-gtk3
          libdrm
          libepoxy
          libevdev
          libevent
          libgcc.lib
          libgcrypt
          libGL
          libglvnd
          libgpg-error
          libgudev
          libjpeg8
          libffi_3_3
          libmanette
          libnotify
          libopus
          libpng
          libpulseaudio
          libpsl
          libsecret
          libsoup_3
          libtasn1
          libunwind
          libusb1
          libuuid
          libwebp
          libxkbcommon
          libxml2
          libxslt
          mesa
          nghttp2.lib
          nspr
          nss
          openssl
          pango
          # I am sorry, but this works. Okay?
          (pcre.out.overrideAttrs {
            # nix-ld only looks at top level lib and share
            postInstall = ''
              ln -s $out/lib/libpcre.so.1.2.13 $out/lib/libpcre.so.3
            '';
          })
          pciutils
          pipewire
          # TODO: find more "official" ditribution of libwebp.so.6
          rigsofrods-bin
          sqlite
          stdenv.cc.cc
          systemd
          systemdLibs
          vulkan-loader
          webkitgtk_4_1
          woff2.lib
          xorg.libICE
          xorg.libX11
          xorg.libxcb
          xorg.libXcomposite
          xorg.libXdamage
          xorg.libXext
          xorg.libXfixes
          xorg.libXi
          xorg.libxkbfile
          xorg.libXrandr
          xorg.libXrender
          xorg.libXScrnSaver
          xorg.libxshmfence
          xorg.libXtst
          zlib
          (rigsofrods-bin.overrideAttrs {
            # nix-ld only looks at top level lib and share
            postInstall = ''
              mv $out/share/rigsofrods/lib $out/lib
            '';
          })
        ];
      };
      seahorse.enable = true;
      # installs a special kernel module to enable tracing
      sysdig.enable = true;
      # must be enabled system-wide in order to be a default shell
      # additional settings should occur in home-manager
      zsh.enable = true;
    };

    hardware = {
      enableAllFirmware = true;
      bluetooth.enable = true;
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
        package = config.boot.kernelPackages.nvidiaPackages.production;
        # forceFullCompositionPipeline = true;
      };
      nvidia-container-toolkit.enable = true;
    };

    services = {
      orca.enable = true;
      blueman.enable = true;
      flatpak.enable = true;
      geoclue2.enable = true;
      plover.enable = true;

      gnome.gnome-keyring.enable = true;
      hardware.openrgb = {
        enable = true;
        package = pkgs.pkgs-mine.openrgb-appimage;
      };
      openssh = {
        enable = true;
        # since I use zellij, I don't mind disconnecting often and just
        # reconnecting to my session; I want to avoid stale/unresponsive
        # connections
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
      udisks2.enable = true;
      # Configure keymap in X11
      xserver = {
        xkb.layout = "us";
        xkb.variant = "";
        videoDrivers = [ "nvidia" ];
      };
    };

    location = {
      longitude = 40.0;
      latitude = 90.0;
    };

    security = {
      pam.services.swaylock.text = # sh
        ''
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
        source = lib.getExe pkgs.noisetorch;
        capabilities = "cap_sys_resource+ep";
      };
    };

    # Just don't change this. There is never a good reason to change this as all updates still
    # apply and changing this just messes things up. It is a state tracker
    system.stateVersion = "23.05"; # Did you read the comment?

    nix = {
      gc = {
        persistent = true; # nixos only
        dates = "weekly"; # nixos only
      };
    };

    # TIP: run `nix run nixpkgs#door-knocker` and check that portal
    # implemenation has expected support
    xdg.portal =
      let
        inherit (inputs.hyprland.packages.${pkgs.system}) hyprland xdg-desktop-portal-hyprland;
      in
      {
        enable = true;
        extraPortals = [
          xdg-desktop-portal-hyprland
          pkgs.xdg-desktop-portal-gnome
        ];
        config =
          let
            common = {
              default = [
                "hyprland"
                "gnome"
              ];
              # TODO: what kinds of other useful settings can I set?
              # "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
            };
          in
          {
            inherit common;
            hyprland = common;
          };
        configPackages = [ hyprland ];
      };
  };
}
