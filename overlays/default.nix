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
