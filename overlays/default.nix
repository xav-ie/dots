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
      inherit (final) system config;
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

    # Update subliminal to latest version (nixpkgs has 2.3.2, but 2.4.0 is available)
    # Also fix missing dependencies: defusedxml, knowit, tomlkit
    python3 = prev.python3.override {
      packageOverrides = pself: psuper: {
        # knowit doesn't exist in nixpkgs, so we need to add it
        knowit = pself.buildPythonPackage rec {
          pname = "knowit";
          version = "0.5.11";
          format = "pyproject";

          src = final.fetchPypi {
            inherit pname version;
            hash = "sha256-kEXWZAsb0A/MSfL36BmSzcbHJ5dn2xmdfztj4vUAe1g=";
          };

          nativeBuildInputs = with pself; [
            poetry-core
          ];

          propagatedBuildInputs = with pself; [
            babelfish
            enzyme
            pymediainfo
            pyyaml
            trakit
          ];
        };

        subliminal = psuper.subliminal.overridePythonAttrs (_old: {
          version = "2.4.0";
          src = final.fetchPypi {
            pname = "subliminal";
            version = "2.4.0";
            hash = "sha256-c99tGUAWbvDizetPjWVaSv4QgtSB7AkK0qnmaxoWIfw=";
          };

          nativeBuildInputs = with pself; [
            hatchling
            hatch-vcs
          ];

          nativeCheckInputs = with pself; [
            colorama
          ];

          propagatedBuildInputs = with pself; [
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
        });
      };
    };
    python3Packages = final.python3.pkgs;
  };
}
