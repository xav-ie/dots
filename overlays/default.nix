toplevel:
let
  inherit (toplevel) inputs;
  # praesidium GPU facts (compute capability, Vulkan ICD) — see the file.
  gpu = import ./../modules/_lib/gpu.nix;
  # crates.io API returns 403 for curl's default User-Agent; route crate
  # downloads via static.crates.io (CDN). Mirrors nixpkgs f830e611. Drop the
  # whole `patchedImportCargoLockFor` mechanism once that commit reaches our
  # nixos-unstable pin.
  # Hashes for git-dep tarballs we can't reach via git fetch (orphan revs that
  # got force-pushed off a branch but are still served via GitHub's archive
  # endpoint). Keyed by commit SHA; values are `nix-prefetch-url --unpack`
  # output for `https://github.com/<owner>/<repo>/archive/<sha>.tar.gz`.
  knownOrphanTarballHashes = {
    # soywod/imap-next — referenced by himalaya's Cargo.lock, no longer
    # reachable from any ref since the alpha.7 bump rewrote history.
    "e9d7db2eac281c0361fc21b92e3d3ed3a6e09f13" = "03hix28b40cisbxym5w67qr75rd3r0ypl8ipbygg5lbvpmcz8wm7";
  };

  # Patch nixpkgs's import-cargo-lock.nix to:
  #   1. Use static.crates.io instead of the API server (mirrors nixpkgs
  #      f830e611 — bypasses the 403 block on curl's default User-Agent).
  #   2. Fall back to builtins.fetchTarball on GitHub's archive endpoint for
  #      git deps, with a pre-baked hash table for known orphan revs so the
  #      fetch is reproducible in pure eval mode (nh, flake check, etc.).
  patchedImportCargoLockFor =
    pkgs:
    (pkgs.runCommand "import-cargo-lock-patched" { } # sh
      ''
        mkdir -p $out
        cp -r ${pkgs.path}/pkgs/build-support/rust/. $out/
        ${pkgs.gnused}/bin/sed -i \
          -e 's|https://crates.io/api/v1/crates|https://static.crates.io/crates|g' \
          -e '/else if allowBuiltinFetchGit then/,/missingHash;/c\
            else if allowBuiltinFetchGit then\
              (let\
                m = builtins.match "https?://github.com/([^/]+)/([^/.]+)(\\.git)?/?" gitParts.url;\
                knownHashes = { ${
                  knownOrphanTarballHashes
                  |> builtins.attrNames
                  |> builtins.map (k: ''"${k}" = "${knownOrphanTarballHashes.${k}}"; '')
                  |> toString
                } };\
              in\
                if m != null && knownHashes ? ''${gitParts.sha} then\
                  builtins.fetchTarball {\
                    url = "https://github.com/" + (builtins.elemAt m 0) + "/" + (builtins.elemAt m 1) + "/archive/" + gitParts.sha + ".tar.gz";\
                    sha256 = knownHashes.''${gitParts.sha};\
                  }\
                else\
                  fetchGit {\
                    inherit (gitParts) url;\
                    rev = gitParts.sha;\
                    allRefs = true;\
                    submodules = true;\
                  })\
            else\
              missingHash;' \
          $out/import-cargo-lock.nix
      ''
    )
    + "/import-cargo-lock.nix";
in
{
  nuenv = inputs.nuenv.overlays.default;

  modifications =
    final: prev:
    let
      # nixpkgs-bleeding pinned to this host's platform via the shared
      # constructor (which bakes in the version pins). CUDA variants pass
      # cudaSupport + capabilities; the plain variant carries package-pin
      # overlays.
      mkBleeding =
        args:
        import ./_bleeding.nix (
          {
            inherit (inputs) nixpkgs-bleeding;
            inherit (final.stdenv.hostPlatform) system;
          }
          // args
        );
    in
    {
      rustPlatform = prev.rustPlatform // {
        importCargoLock = prev.buildPackages.callPackage (patchedImportCargoLockFor prev) {
          inherit (prev) cargo;
        };
      };
      makeRustPlatform =
        args:
        let
          rp = prev.makeRustPlatform args;
        in
        rp
        // {
          importCargoLock = prev.buildPackages.callPackage (patchedImportCargoLockFor prev) {
            inherit (args) cargo;
          };
        };
      alacritty-theme =
        if final.stdenv.isLinux then
          inputs.alacritty-theme.packages.${final.stdenv.hostPlatform.system}
        else
          null;
      ctpv = inputs.ctpv.packages.${final.stdenv.hostPlatform.system}.default;
      generate-kaomoji = inputs.generate-kaomoji.packages.${final.stdenv.hostPlatform.system}.default;
      # Plain bleeding: no CUDA (avoids cache misses), carries package pins.
      pkgs-bleeding = mkBleeding { };
      # Same bleeding channel, but pinned to praesidium's GPU so CUDA packages
      # compile a single arch instead of the full 9-arch fat binary. ~5-9x faster
      # onnxruntime/whisper-cpp builds; the trade-off is these hashes no longer
      # match cuda-maintainers.cachix.org, so they always build locally.
      pkgs-bleeding-cuda = mkBleeding {
        config = {
          cudaSupport = true;
          inherit (gpu) cudaCapabilities;
        };
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

      # sketchybar built from the clean upstream v2.23.0 tag (sketchybar-src) with
      # my fixes fetched straight from the xav-ie fork as `fetchpatch` diffs, each
      # droppable on its own the moment it lands upstream. Pinned by BRANCH (via
      # the GitHub `compare` endpoint) on purpose: pushing to a branch changes the
      # diff and so breaks the hash, forcing a deliberate re-pin here rather than
      # silently drifting. fetchpatch re-normalizes GitHub's generated diff so the
      # output hash is stable unless the content actually changes. v2.23.0 matches
      # nixpkgs' base (no extra nixpkgs patches to preserve).
      # Version string is left as-is: sketchybar bakes "v2.23.0" into its
      # --version output, and nixpkgs' versionCheckPhase greps for it, so a
      # suffixed version would fail the check.
      sketchybar = prev.sketchybar.overrideAttrs (old: {
        src = inputs.sketchybar-src;
        patches = (old.patches or [ ]) ++ [
          # Align right/center text by the typographic advance width instead of
          # the glyph-path (ink) width, so right-aligned tabular-figure labels
          # (e.g. the volume "25%"/"31%") stop wobbling ±1px between values.
          # Diff of the branch against the v2.23.0 base it forks from.
          (final.fetchpatch {
            name = "sketchybar-text-align-advance-width.patch";
            url = "https://github.com/xav-ie/SketchyBar/compare/v2.23.0...fix/tabular-align-advance-width.diff";
            hash = "sha256-Hg2vW+aGZLkKTD0d4Pncv51QfYpFZg0d3rQvlXxUZWc=";
          })
          # The bar context is kCGInterpolationNone globally to keep pixel-exact
          # PNG icons crisp; app icons come from NSImage at native rep size and get
          # scaled down, so they need kCGInterpolationHigh for the draw or they
          # look jagged/aliased. Tracked as upstream PR #832 (diff against master);
          # the hash breaks if the PR is updated. Drop this once it merges.
          (final.fetchpatch {
            name = "sketchybar-image-hq-app-icon-sampling.patch";
            url = "https://github.com/FelixKratz/SketchyBar/pull/832.diff";
            hash = "sha256-pgY6xGTmNu9o7TXxvECFqSCfNNmLBsj1ZoxKOh+ytao=";
          })
        ];
      });

      # Inter with tabular figures (`tnum`) baked in as the default, as a single
      # static Light instance. Used only by sketchybar's label font so the clock/
      # battery digits stop jittering; plain `inter` is left untouched for
      # hyprlock et al. We freeze the feature by hand with fonttools (remap the
      # cmap through the tnum SingleSubst lookup) because opentype-feature-freezer
      # 1.32 is broken against current fonttools. Family is renamed to
      # "Inter Tabular" so it never collides with the real Inter.
      inter-tabular =
        let
          py = final.python3.withPackages (ps: [ ps.fonttools ]);
          freeze =
            final.writeText "freeze-tnum.py" # py
              ''
                import sys
                from fontTools.ttLib import TTFont

                infile, outfile, family, style = sys.argv[1:5]
                f = TTFont(infile)

                # Collect glyph->glyph substitutions from the tnum feature's
                # SingleSubst lookups (Inter's tabular figures are a 1:1 mapping).
                gsub = f["GSUB"].table
                lks = set()
                for fr in gsub.FeatureList.FeatureRecord:
                    if fr.FeatureTag == "tnum":
                        lks.update(fr.Feature.LookupListIndex)
                m = {}
                for li in sorted(lks):
                    lk = gsub.LookupList.Lookup[li]
                    if lk.LookupType == 1:
                        for st in lk.SubTable:
                            m.update(getattr(st, "mapping", {}))
                if not m:
                    raise SystemExit("no tnum substitutions found")

                # Remap every cmap subtable so default codepoints resolve to the
                # tabular glyphs.
                for st in f["cmap"].tables:
                    for cp, g in list(st.cmap.items()):
                        if g in m:
                            st.cmap[cp] = m[g]

                # Rewrite the name table to a clean, collision-free identity.
                ps = family.replace(" ", "") + "-" + style.replace(" ", "")
                full = family if style == "Regular" else family + " " + style
                name = f["name"]
                name.names = []
                vals = {1: family, 2: style, 4: full, 6: ps, 16: family, 17: style}
                for nid, v in vals.items():
                    name.setName(v, nid, 3, 1, 0x409)  # Windows / Unicode / en-US
                    name.setName(v, nid, 1, 0, 0)      # Mac / Roman / en

                f.save(outfile)
              '';
        in
        final.runCommand "inter-tabular"
          {
            nativeBuildInputs = [ py ];
            meta.description = "Inter Light with tabular figures frozen on (sketchybar labels)";
          }
          # sh
          ''
            light=light.ttf
            # Instance a static Light (wght=300) cut from the variable font.
            ${py}/bin/fonttools varLib.instancer \
              ${final.inter}/share/fonts/truetype/InterVariable.ttf \
              wght=300 -o "$light"
            out=$out/share/fonts/truetype
            mkdir -p "$out"
            ${py}/bin/python3 ${freeze} "$light" "$out/InterTabular.ttf" "Inter Tabular" "Regular"
          '';
      beads = inputs.beads.packages.${final.stdenv.hostPlatform.system}.default;
      herdr = inputs.herdr.packages.${final.stdenv.hostPlatform.system}.default;
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
      atuin = inputs.atuin.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
        pname = "atuin";
        version = "18.16.0";
        # Layer my unmerged PRs on top of upstream main: three pty-proxy fixes
        # plus a nushell ESC-char fix. They touch non-overlapping regions and
        # don't add vendored deps (percent-encoding is already in the lock), so
        # they apply cleanly. Drop each patch once it merges upstream. (#3327
        # --shell already merged, so it's no longer here.)
        patches = (old.patches or [ ]) ++ [
          (final.fetchpatch {
            name = "atuin-pr3529-pty-proxy-pixel-size.patch";
            url = "https://github.com/atuinsh/atuin/pull/3529.patch";
            hash = "sha256-2Bz8TMcDgz6qxAzwjSfyQf0pYn+LH/nAfWXPyZZGGmo=";
          })
          (final.fetchpatch {
            name = "atuin-pr3461-pty-proxy-osc7.patch";
            url = "https://github.com/atuinsh/atuin/pull/3461.patch";
            hash = "sha256-TX8KlehDImXYm+FDVMByF+OUJ6IY2QatagkY5Q2/fr4=";
          })
          # #3510's OSC 133 nushell helpers call `(char esc)`, which is not a
          # valid Nushell named character — `atuin init nu` errors on every nu
          # version. This switches it to `(char -u 1b)`. Drop once merged.
          (final.fetchpatch {
            name = "atuin-pr3530-nu-char-esc.patch";
            url = "https://github.com/atuinsh/atuin/pull/3530.patch";
            hash = "sha256-c565RbIGBOUNi1fgmuqM/0xonS2PWyc80OlyuADLy7k=";
          })
          # pty-proxy spawns the inner shell but never sets SHELL on it, so the
          # child — and `$SHELL -c` consumers like fzf's `become` — inherit a
          # stale shell from the parent env. Point SHELL at the shell we spawn.
          (final.fetchpatch {
            name = "atuin-pty-proxy-shell-env.patch";
            url = "https://github.com/atuinsh/atuin/pull/3548.patch";
            hash = "sha256-WRibHKn9Xd3OdsbcAkd8xqMfJJHrV2lja2XSkx39cxU=";
          })
        ];
        # #3461 adds `percent-encoding` to atuin-pty-proxy's Cargo.lock dep list.
        # The crate is already vendored (used transitively elsewhere), but
        # importCargoLock's consistency check diffs the patched lockfile against
        # the vendored copy and fails on the textual mismatch. Re-sync the
        # vendored copy — runs before cargoSetupPostPatchHook validates. Drop
        # this together with the #3461 patch once that PR merges.
        postPatch = (old.postPatch or "") + ''
          cp Cargo.lock "$cargoDepsCopy/Cargo.lock"
        '';
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
              srcs =
                [
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
                ]
                |> map (args: fetchJammyDeb args.path args.hash);
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
                # sh
                ''
                  mkdir -p $out/lib/gstreamer-1.0
                  for plugin in ${neededPlugins |> builtins.concatStringsSep " "}; do
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
                [ gst-plugins ] |> final.lib.makeLibraryPath
              }:${libexecBundled}:/run/opengl-driver/lib" \
              --prefix PATH : "${
                [
                  final.ydotool
                  final.wtype
                ]
                |> final.lib.makeBinPath
              }" \
              --prefix XDG_DATA_DIRS : "${
                [
                  final.gsettings-desktop-schemas
                  final.gtk3
                  final.shared-mime-info
                  final.hicolor-icon-theme
                ]
                |> final.lib.concatMapStringsSep ":" (p: "${p}/share")
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
              --set VK_ICD_FILENAMES "${gpu.vulkanIcd}" \
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
              --set VK_ICD_FILENAMES "${gpu.vulkanIcd}"
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
