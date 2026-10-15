{
  flake.modules.nixos.linux =
    { config, pkgs, ... }:
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
          # The session's own mesa, not a second stock one.
          config.hardware.graphics.package
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
          sqlite
          stdenv.cc.cc
          systemd
          systemdLibs
          vulkan-loader
          webkitgtk_4_1
          woff2.lib
          libice
          libx11
          libxcb
          libxcomposite
          libxdamage
          libxext
          libxfixes
          libxi
          libxkbfile
          libxrandr
          libxrender
          libxscrnsaver
          libxshmfence
          libxtst
          zlib
          # libwebp.so.6 (the pre-1.0 ABI) for old prebuilt binaries; nixpkgs only
          # ships .so.7. Rigs of Rods bundles it, so copy out just that library.
          (runCommand "libwebp6" { } ''
            install -Dm555 -t $out/lib ${rigsofrods-bin}/share/rigsofrods/lib/libwebp.so.6*
          '')
        ];
      };
    };
}
