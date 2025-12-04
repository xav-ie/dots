toplevel:
let
  inherit (toplevel) inputs;
in
{
  nur = inputs.nur.overlays.default;
  nuenv = inputs.nuenv.overlays.default;

  modifications = final: prev: {
    alacritty-theme =
      if final.stdenv.isLinux then inputs.alacritty-theme.packages.${final.system} else null;
    ctpv = inputs.ctpv.packages.${final.system}.default;
    generate-kaomoji = inputs.generate-kaomoji.packages.${final.system}.default;
    pkgs-bleeding = import inputs.nixpkgs-bleeding {
      inherit (final) system;
      config.allowUnfree = true;
      # Don't inherit cudaSupport/cudaCapabilities to avoid cache misses
    };
    pkgs-mine = toplevel.self.packages.${final.system};
    # Fix govee-local-api not setting the lights all the time
    # pkgs-homeassistant needing because poetry-core>=2.0.0 is not on stable
    # and I don't feel like overriding *another* sub-dependency
    home-assistant =
      if final.stdenv.isLinux then
        let
          pkgs-homeassistant = import inputs.nixpkgs-homeassistant {
            inherit (final) system config;
          };
        in
        pkgs-homeassistant.home-assistant.override {
          packageOverrides = self: _: {
            govee-local-api = pkgs-homeassistant.python313Packages.govee-local-api.overridePythonAttrs (_: {
              version = "2.0.2";
              src = final.fetchFromGitHub {
                owner = "akash329d";
                repo = "govee-local-api";
                rev = "develop";
                hash = "sha256-ChI/rIZwT/YMXFD83N1/cIIYkio318S3p1IgVu+P1sY=";
              };
            });
            protobuf = pkgs-homeassistant.python313Packages.protobuf.overridePythonAttrs (_old: {
              version = "6.31.1";
              src = final.fetchPypi {
                pname = "protobuf";
                version = "6.31.1";
                hash = "sha256-2MrEyYLwuVek3HOoDi6iT6sI5nnA3p3rg19KEtaaypo=";
              };
            });
            pyatv =
              (pkgs-homeassistant.python313Packages.pyatv.override {
                inherit (self) protobuf;
              }).overridePythonAttrs
                (_old: {
                  version = "0.16.1";
                  src = final.fetchFromGitHub {
                    owner = "postlund";
                    repo = "pyatv";
                    rev = "v0.16.1";
                    hash = "sha256-b5u9u5CD/1W422rCxHvoyBqT5CuBAh68/EUBzNDcXoE=";
                  };
                });
          };
          # home-assistant freaks out if these are not added
          extraPackages =
            ps: with ps; [
              getmac
              spotifyaio
              govee-ble
            ];
        }
      else
        null;
    notification-cleaner =
      if final.stdenv.isDarwin then
        inputs.notification-cleaner.packages.${final.system}.default
      else
        null;
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
    zjstatus = inputs.zjstatus.packages.${final.system}.default;

    # Custom nix-output-monitor with Nerd Font icons
    # https://haseebmajid.dev/posts/2025-08-10-til-how-to-change-emojis-in-nh/
    nix-output-monitor = prev.nix-output-monitor.overrideAttrs (old: {
      postPatch = old.postPatch or "" + ''
        substituteInPlace lib/NOM/Print.hs \
          --replace 'down = "↓"' 'down = "\xf072e"' \
          --replace 'up = "↑"' 'up = "\xf0737"' \
          --replace 'clock = "⏱"' 'clock = "\xf520"' \
          --replace 'running = "⏵"' 'running = "\xf04b"' \
          --replace 'done = "✔"' 'done = "\xf00c"' \
          --replace 'todo = "⏸"' 'todo = "\xf04d"' \
          --replace 'warning = "⚠"' 'warning = "\xf071"' \
          --replace 'average = "∅"' 'average = "\xf1da"' \
          --replace 'bigsum = "∑"' 'bigsum = "\xf04a0"'
      '';
    });

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
