toplevel:
let
  inherit (toplevel) inputs;
in
{
  nuenv = inputs.nuenv.overlays.default;

  modifications = final: prev: {
    alacritty-theme =
      if final.stdenv.isLinux then
        inputs.alacritty-theme.packages.${final.stdenv.hostPlatform.system}
      else
        null;
    ctpv = inputs.ctpv.packages.${final.stdenv.hostPlatform.system}.default;
    generate-kaomoji = inputs.generate-kaomoji.packages.${final.stdenv.hostPlatform.system}.default;
    pkgs-bleeding = import inputs.nixpkgs-bleeding {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
      # Don't inherit cudaSupport/cudaCapabilities to avoid cache misses
    };
    pkgs-mine = toplevel.self.packages.${final.stdenv.hostPlatform.system};
    notification-cleaner =
      if final.stdenv.isDarwin then
        inputs.notification-cleaner.packages.${final.stdenv.hostPlatform.system}.default
      else
        null;
    uair = prev.uair.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        (final.fetchpatch {
          url = "https://github.com/metent/uair/pull/31.patch";
          hash = "sha256-sxvuq3B/3vb46LgTg+geHaCwkDYTHUxmUT7EIpEda8o=";
        })
      ];
    });
    orca = prev.orca.overrideAttrs (old: {
      propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
        final.python3.pkgs.wrapPython
      ];
      postFixup = (old.postFixup or "") + ''
        wrapProgram $out/bin/.orca-wrapped \
          --prefix PYTHONPATH : "${final.speechd}/lib/${final.python3.libPrefix}/site-packages"
      '';
    });
    writeNuApplication = final.nuenv.writeShellApplication;
    beads = inputs.beads.packages.${final.stdenv.hostPlatform.system}.default;
    himalaya =
      let
        base = inputs.himalaya-latest.packages.${final.stdenv.hostPlatform.system}.default;
      in
      base.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          emailLibDir=$(find /build -maxdepth 3 -name 'email-lib-*' -type d | head -1)
          # Replace vendored email-lib src with pimalaya-core flake input.
          # Remove this override once email-lib > 0.27.0 is released.
          cp -rT ${inputs.pimalaya-core}/email/src "$emailLibDir/src"
        '';
      });
    neverest = inputs.neverest.packages.${final.stdenv.hostPlatform.system}.default;
    zjstatus = inputs.zjstatus.packages.${final.stdenv.hostPlatform.system}.default;
    # atuin version (matches flake URL: github:atuinsh/atuin/v18.13.3)
    atuin =
      let
        base = inputs.atuin.packages.${final.stdenv.hostPlatform.system}.default;
      in
      base.overrideAttrs (old: {
        version = "18.13.3";
        patches = (old.patches or [ ]) ++ [
          (final.fetchpatch {
            url = "https://github.com/atuinsh/atuin/pull/3327.patch";
            hash = "sha256-lj+sE9lBAYMGE6dkt0mtyIAdoRt8zHJoBif5a9P91eQ=";
          })
          (final.fetchpatch {
            url = "https://github.com/atuinsh/atuin/pull/3330.patch";
            hash = "sha256-CUFv036TwJI/a0KUGhQZl5Rt/buqG8FrdZtNaTyyky8=";
          })
        ];
      });

    voquill =
      let
        pname = "voquill";
        version = "0.0.588";
        debLibDir = "usr/lib/x86_64-linux-gnu";

        src = final.fetchurl {
          url = "https://github.com/voquill/voquill/releases/download/desktop-v${version}/voquill-desktop_${version}_amd64.AppImage";
          hash = "sha256-y1WXzLn8IrPe3f+YLEQ+ZD8ciR6uH101gt2DvVQzaKg=";
        };
        extracted = final.appimageTools.extract { inherit pname version src; };
        bundledLibs = "${extracted}/usr/lib";

        # Ubuntu 22.04 (jammy) debs — ABI-compatible with bundled glib 2.72 / gstreamer 1.20.3
        fetchJammyDeb =
          path: hash:
          final.fetchurl {
            url = "http://archive.ubuntu.com/ubuntu/${path}";
            inherit hash;
          };

        # Shared config for derivations that patch Ubuntu deb contents
        jammyDebPatchBase = {
          nativeBuildInputs = [
            final.dpkg
            final.autoPatchelfHook
          ];
          autoPatchelfIgnoreMissingDeps = true;
          appendRunpaths = [ bundledLibs ];
          dontStrip = true;
        };

        # dconf GIO module (matches bundled glib 2.72)
        dconf-gio = final.stdenv.mkDerivation (
          jammyDebPatchBase
          // {
            name = "voquill-dconf-gio";
            src = fetchJammyDeb "pool/main/d/dconf/dconf-gsettings-backend_0.40.0-3ubuntu0.1_amd64.deb" "sha256-kGMvuzpoZdNqjsF+QVL0Ge/X6Udoxopef6W2DNzkepQ=";
            buildInputs = [ final.stdenv.cc.cc.lib ];
            unpackPhase = "dpkg-deb -x $src unpacked";
            installPhase = ''
              mkdir -p $out/lib/gio/modules
              cp unpacked/${debLibDir}/gio/modules/libdconfsettings.so $out/lib/gio/modules/
            '';
          }
        );

        # GStreamer plugins and runtime libraries
        gst-plugins = final.stdenv.mkDerivation (
          jammyDebPatchBase
          // {
            name = "voquill-gst-plugins";
            srcs = map (args: fetchJammyDeb args.path args.hash) [
              # Plugins
              {
                path = "pool/main/g/gst-plugins-base1.0/gstreamer1.0-plugins-base_1.20.1-1ubuntu0.6_amd64.deb";
                hash = "sha256-f3oXX96vKnTW05nDz5TDeZetH836+Af5WeRsYDUFvqE=";
              }
              {
                path = "pool/main/g/gst-plugins-good1.0/gstreamer1.0-plugins-good_1.20.3-0ubuntu1.5_amd64.deb";
                hash = "sha256-S6GUKououaeWocKFQehNGsS6ygZ025qnD0S128ItXKo=";
              }
              {
                path = "pool/universe/g/gst-plugins-bad1.0/gstreamer1.0-plugins-bad_1.20.3-0ubuntu1.1_amd64.deb";
                hash = "sha256-Po5LJPfuKW0nNiXgQhXR+LePF38qaCpUTyYFW8cISao=";
              }
              {
                path = "pool/main/g/gst-plugins-good1.0/gstreamer1.0-pulseaudio_1.20.3-0ubuntu1.5_amd64.deb";
                hash = "sha256-iTcVcSlm3j26hg8OlywCvBd18/gR1jp7eb60wCkdEmg=";
              }
              # Runtime libraries (libgstriff, libgstnet, libgstrtp, etc.)
              {
                path = "pool/main/g/gst-plugins-base1.0/libgstreamer-plugins-base1.0-0_1.20.1-1ubuntu0.6_amd64.deb";
                hash = "sha256-MJFTjtixk8Dbt1fFoRtQPZupfnx3v5OJFaJhj3NhclY=";
              }
              {
                path = "pool/universe/g/gst-plugins-bad1.0/libgstreamer-plugins-bad1.0-0_1.20.3-0ubuntu1.1_amd64.deb";
                hash = "sha256-K0Y9UVSEGVF+U1bziT+uo4bk9A+5GvLrCuhuRE02td0=";
              }
              {
                path = "pool/main/g/gstreamer1.0/libgstreamer1.0-0_1.20.3-0ubuntu1.1_amd64.deb";
                hash = "sha256-Ry0ldfnmuJQ2ECOZWw3NGuKP49QAXe2BIx1O/HgzRG0=";
              }
            ];
            buildInputs = [
              final.alsa-lib
              final.bzip2
              final.gsm
              final.libdrm
              final.libgudev
              final.libjack2
              final.libjpeg
              final.libpng
              final.libpulseaudio
              final.libv4l
              final.libva
              final.mesa
              final.orc
              final.stdenv.cc.cc.lib
              final.vulkan-loader
              final.xorg.libX11
              final.xorg.libxcb
              final.zlib
            ];
            runtimeDependencies = [ bundledLibs ];
            unpackPhase = ''
              for src in $srcs; do
                dpkg-deb -x "$src" unpacked
              done
            '';
            installPhase =
              let
                # Only install needed plugins (avoids warnings for niche codecs)
                neededPlugins = [
                  # gst-plugins-base
                  "libgstaudioconvert"
                  "libgstaudioresample"
                  "libgstplayback"
                  "libgstvolume"
                  "libgsttypefindfunctions"
                  "libgstapp"
                  "libgstalsa"
                  "libgstcoreelements"
                  # gst-plugins-good
                  "libgstautodetect"
                  "libgstpulseaudio"
                  "libgstwavparse"
                  "libgstaudioparsers"
                  "libgstid3demux"
                  "libgstmpg123"
                  "libgstogg"
                  "libgstopus"
                  "libgstvorbis"
                  "libgstflac"
                  "libgstaudiofx"
                  "libgstlame"
                  "libgstisomp4"
                  "libgstmatroska"
                  "libgstwavenc"
                  # gst-plugins-bad
                  "libgstdebugutilsbad"
                  "libgstsubenc"
                ];
              in
              ''
                mkdir -p $out/lib/gstreamer-1.0
                for plugin in ${builtins.concatStringsSep " " neededPlugins}; do
                  [ -f "unpacked/${debLibDir}/gstreamer-1.0/$plugin.so" ] && \
                    cp "unpacked/${debLibDir}/gstreamer-1.0/$plugin.so" $out/lib/gstreamer-1.0/
                done
                # Support libraries (libgstriff, libgstnet, libgstrtp, etc.)
                cp unpacked/${debLibDir}/libgst*.so* $out/lib/ 2>/dev/null || true
              '';
          }
        );

        libexec = "$out/libexec/voquill";
        libexecBundled = "${libexec}/lib";
      in
      final.stdenv.mkDerivation {
        inherit pname version;
        src = extracted;

        nativeBuildInputs = [
          final.autoPatchelfHook
          final.makeWrapper
        ];

        buildInputs = [
          final.alsa-lib
          final.cairo
          final.e2fsprogs
          final.expat
          final.fontconfig
          final.freetype
          final.fribidi
          final.glib
          final.gtk-layer-shell
          final.gtk3
          final.harfbuzz
          final.libdrm
          final.libgpg-error
          final.mesa
          final.pango
          final.stdenv.cc.cc.lib
          final.vulkan-loader
          final.xorg.libX11
          final.xorg.libxcb
          final.zlib
        ];

        installPhase = ''
          runHook preInstall

          mkdir -p $out/bin $out/share ${libexec}
          cp -r usr/lib ${libexec}/
          cp -r usr/bin ${libexec}/

          chmod +x ${libexec}/bin/*
          find ${libexecBundled} -name 'voquill-gtk-pill' -exec chmod +x {} +
          find ${libexecBundled} -name 'WebKit*Process' -exec chmod +x {} +

          # WebKit resolves subprocess paths relative to the binary dir (././/lib/...)
          ln -s ../lib ${libexec}/bin/lib

          cp -r usr/share/applications usr/share/icons $out/share/

          # Combine bundled GIO modules (gnutls) with dconf from Ubuntu 22.04
          mkdir -p ${libexecBundled}/gio-modules-combined
          cp ${libexecBundled}/x86_64-linux-gnu/gio/modules/*.so ${libexecBundled}/gio-modules-combined/
          cp ${dconf-gio}/lib/gio/modules/*.so ${libexecBundled}/gio-modules-combined/

          # Rewrite the bundled pixbuf loaders cache to use the installed paths
          substituteInPlace ${libexecBundled}/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache \
            --replace-quiet '/usr/lib/x86_64-linux-gnu' "${libexecBundled}/x86_64-linux-gnu"

          makeWrapper ${libexec}/bin/voquill-desktop $out/bin/voquill \
            --run "cd '${libexec}'" \
            --prefix LD_LIBRARY_PATH : "${
              final.lib.makeLibraryPath [ gst-plugins ]
            }:${libexecBundled}:/run/opengl-driver/lib" \
            --prefix PATH : "${
              final.lib.makeBinPath [
                final.ydotool
                final.wtype
              ]
            }" \
            --prefix XDG_DATA_DIRS : "${
              final.lib.concatMapStringsSep ":" (p: "${p}/share") [
                final.gsettings-desktop-schemas
                final.gtk3
                final.shared-mime-info
                final.hicolor-icon-theme
              ]
            }:${final.gsettings-desktop-schemas}/share/gsettings-schemas/${final.gsettings-desktop-schemas.name}:${final.gtk3}/share/gsettings-schemas/${final.gtk3.name}" \
            --set GDK_PIXBUF_MODULE_FILE "${libexecBundled}/x86_64-linux-gnu/gdk-pixbuf-2.0/2.10.0/loaders.cache" \
            --set GIO_MODULE_DIR "${libexecBundled}/gio-modules-combined" \
            --unset GIO_EXTRA_MODULES \
            --set GST_PLUGIN_PATH_1_0 "${gst-plugins}/lib/gstreamer-1.0" \
            --set GST_PLUGIN_SYSTEM_PATH_1_0 "" \
            --set GST_REGISTRY_FORK "no" \
            --set WEBKIT_EXEC_PATH "${libexecBundled}/x86_64-linux-gnu/webkit2gtk-4.1" \
            --set WEBKIT_DISABLE_DMABUF_RENDERER 1 \
            --set XKB_CONFIG_ROOT "${final.xkeyboard_config}/share/X11/xkb" \
            --set VK_ICD_FILENAMES "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json" \
            --set YDOTOOL_SOCKET "/run/ydotoold/socket"

          substituteInPlace $out/share/applications/voquill-desktop.desktop \
            --replace-fail 'Exec=voquill-desktop' 'Exec=voquill' \
            --replace-fail 'Name=voquill-desktop' 'Name=Voquill'

          runHook postInstall
        '';

        dontStrip = true;
      };

    voxtype =
      let
        voxtype-src = final.fetchFromGitHub {
          owner = "peteonrails";
          repo = "voxtype";
          tag = "v0.6.5";
          hash = "sha256-gY5gP+F3SbCZsG/jaOHnEu291q6akg1M5c4BebRSpvI=";
        };
      in
      final.pkgs-bleeding.voxtype.overrideAttrs (old: {
        version = "0.6.5";
        src = voxtype-src;
        cargoBuildFeatures = [ "gpu-vulkan" ];
        cargoCheckFeatures = [ "gpu-vulkan" ];
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          final.shaderc
          final.vulkan-headers
        ];
        buildInputs = (old.buildInputs or [ ]) ++ [
          final.vulkan-loader
          final.vulkan-headers
        ];
        cargoDeps = final.rustPlatform.fetchCargoVendor {
          src = voxtype-src;
          name = "voxtype-0.6.5-vendor";
          hash = "sha256-X6TYlmHjLvsUYlxz4WbzHptKyQZHIBt8u1lLqrS/nz0=";
        };
        postInstall = (old.postInstall or "") + ''
          wrapProgram $out/bin/voxtype \
            --prefix LD_LIBRARY_PATH : "${final.vulkan-loader}/lib" \
            --set VK_ICD_FILENAMES "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
        '';
      });

    inherit (final.pkgs-mine)
      nix-output-monitor
      claude-code
      claude-code-npm
      claude-code-update
      ;

    # Custom subliminal 2.4.0 with fixed dependencies for mpv autosub
    # This is a standalone package that doesn't affect the global python3
    subliminal-custom = final.python3Packages.toPythonApplication (
      final.python3.pkgs.buildPythonPackage rec {
        pname = "subliminal";
        version = "2.4.0";
        format = "pyproject";

        src = final.fetchPypi {
          inherit pname version;
          hash = "sha256-c99tGUAWbvDizetPjWVaSv4QgtSB7AkK0qnmaxoWIfw=";
        };

        nativeBuildInputs = with final.python3Packages; [
          hatchling
          hatch-vcs
        ];

        nativeCheckInputs = with final.python3Packages; [
          colorama
        ];

        # knowit doesn't exist in nixpkgs, so we need to create it inline
        propagatedBuildInputs =
          let
            knowit = final.python3Packages.buildPythonPackage rec {
              pname = "knowit";
              version = "0.5.11";
              format = "pyproject";

              src = final.fetchPypi {
                inherit pname version;
                hash = "sha256-kEXWZAsb0A/MSfL36BmSzcbHJ5dn2xmdfztj4vUAe1g=";
              };

              nativeBuildInputs = with final.python3Packages; [
                poetry-core
              ];

              propagatedBuildInputs = with final.python3Packages; [
                babelfish
                enzyme
                pymediainfo
                pyyaml
                trakit
              ];
            };
          in
          with final.python3Packages;
          [
            babelfish
            beautifulsoup4
            chardet
            click
            click-option-group
            defusedxml
            dogpile-cache
            guessit
            knowit
            platformdirs
            pysubs2
            requests
            srt
            stevedore
            tomlkit
          ];
      }
    );
  };
}
