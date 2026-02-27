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
          hash = "sha256-p96z3vfsOT9Rz4GDQ8P+hZTJ7QdEGRooOmidfSHT8aI=";
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
        # https://github.com/pimalaya/core/pull/44
        threadingPatch = final.fetchpatch {
          url = "https://github.com/pimalaya/core/pull/44.patch";
          hash = "sha256-rc5ifhBo+AHhSia6LaQf9gCSPYn4dwUhlvTzuoZxKvc=";
          includes = [ "email/src/email/envelope/thread/mod.rs" ];
        };
      in
      base.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          emailLibDir=$(find /build -maxdepth 3 -name 'email-lib-*' -type d | head -1)
          patch -p2 -d "$emailLibDir" < ${threadingPatch}
        '';
      });
    neverest = inputs.neverest.packages.${final.stdenv.hostPlatform.system}.default;
    zjstatus = inputs.zjstatus.packages.${final.stdenv.hostPlatform.system}.default;

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
