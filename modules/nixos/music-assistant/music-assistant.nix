{
  flake.modules.nixos.praesidium =
    { lib, pkgs, ... }:
    let
      airplay-cli = pkgs.airplay-cli.overrideAttrs (_: {
        version = "0.5.8";
        src = pkgs.fetchFromGitHub {
          owner = "music-assistant";
          repo = "airplay-cli";
          tag = "v0.5.8";
          fetchSubmodules = true;
          hash = "sha256-t6VUcJrfOCckslEfJou/RpxvmATfSAH2RReM+M1xXro=";
        };
      });
    in
    {
      # The module puts pkgs.airplay-cli on PATH; put the matching version ahead of it.
      systemd.services.music-assistant.path = lib.mkBefore [ airplay-cli ];

      services.local-networking.proxies.music-assistant = {
        subdomain = "music";
        port = 8095;
      };

      services.music-assistant = {
        enable = true;
        # 2.10.7 ahead of nixpkgs (2.10.6): AirPlay speakers are released when a stream
        # ends, and AirPlay stays in sync with Sendspin players. Drop once nixpkgs has it.
        # makeOverridable keeps .override, which the module uses to add the providers.
        package = pkgs.lib.makeOverridable (
          args:
          let
            python3Packages = pkgs.python3Packages.overrideScope (
              _: prev: {
                aiosendspin = prev.aiosendspin.overridePythonAttrs (old: {
                  version = "10.2.0";
                  # Timing-sensitive; flaky under a loaded build sandbox.
                  disabledTests = (old.disabledTests or [ ]) ++ [
                    "test_format_change_during_inflight_commit_aborts_old_format_delivery"
                  ];
                  src = pkgs.fetchFromGitHub {
                    owner = "Sendspin";
                    repo = "aiosendspin";
                    tag = "10.2.0";
                    hash = "sha256-CI8eUzKXiabd2I65cABYMTnDZUD54Et36zRiFJlSzz8=";
                  };
                });
              }
            );
            frontend = python3Packages.buildPythonPackage {
              pname = "music-assistant-frontend";
              version = "2.17.297.post1";
              pyproject = true;
              src = python3Packages.fetchPypi {
                pname = "music_assistant_frontend";
                version = "2.17.297.post1";
                hash = "sha256-52iGo3vB23xz9oMSRgkAgPHIeiGzrWHYDbnTiyAYuzU=";
              };
              build-system = [ python3Packages.setuptools ];
              doCheck = false;
            };
          in
          (pkgs.music-assistant.override (args // { inherit airplay-cli python3Packages; }))
          .overridePythonAttrs
            (old: {
              version = "2.10.7";
              src = pkgs.fetchFromGitHub {
                owner = "music-assistant";
                repo = "server";
                tag = "2.10.7";
                hash = "sha256-KIlRSzDKoQebTt5c7Ofs4j1aMK4UxfCcRjqozyYaN1o=";
              };
              # nixpkgs' patches that no longer apply, rebased onto 2.10.7.
              patches = map (
                patch:
                if pkgs.lib.hasSuffix "cliairplay.patch" (toString patch) then
                  ./cliairplay.patch
                else if pkgs.lib.hasSuffix "dont-install-deps.patch" (toString patch) then
                  ./dont-install-deps.patch
                else
                  patch
              ) old.patches;
              # Mocks _install_packages, which dont-install-deps.patch removes.
              disabledTests = (old.disabledTests or [ ]) ++ [
                "test_init_distinguishes_expired_cookies_from_missing_premium"
              ];
              dependencies = map (
                dep: if (dep.pname or "") == "music-assistant-frontend" then frontend else dep
              ) old.dependencies;
            })
        ) { };
        # Players pull audio from the stream port (8097), so it must be reachable on the LAN.
        openFirewall = true;
        providers = [
          "airplay"
          "chromecast"
          "hass"
          "hass_players"
          "radiobrowser"
          "ytmusic"
        ];
      };

      # YouTube streams need a proof of origin token; the ytmusic provider asks this
      # server at its default 127.0.0.1:4416. Unauthenticated, so loopback only.
      # The image tracks the bgutil-ytdlp-pot-provider plugin version in nixpkgs.
      virtualisation.oci-containers.containers.bgutil-pot-provider = {
        image = "docker.io/brainicism/bgutil-ytdlp-pot-provider:2.0.0";
        ports = [ "127.0.0.1:4416:4416" ];
        extraOptions = [ "--init" ];
      };
    };
}
