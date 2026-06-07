{
  flake.modules.nixos.linux =
    { pkgs, ... }:
    {
      config.programs.nix-ld = {
        enable = true;
        package = pkgs.nix-ld;
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
          # TODO: find more "official" distribution of libwebp.so.6
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
    };
}
