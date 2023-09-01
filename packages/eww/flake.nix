{
  description = "A Nix flake for Eww";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: let

    pkgs = nixpkgs.legacyPackages.x86_64-linux;

    buildEww = { rustPlatform, fetchFromGitHub, pkg-config, gtk3, gdk-pixbuf, gtk-layer-shell, stdenv, lib, withWayland ? true }:

      rustPlatform.buildRustPackage rec {
        pname = "eww";
        version = "unstable-2023-06-10";

        src = fetchFromGitHub {
          owner = "ralismark";
          repo = "eww";
          rev = "ef386fc1a3b7736603d55a2157aa1059be373aeb";
          hash = "sha256-0v3bxnC0i6kNXbkIKkUXXZEesMwZg79z7T8kA0oDZsM=";
        };

        cargoHash = "sha256-DLe+bVzc8Gr5MOubR/zzLUl7NRI9uxguWtMCAOcxC4A=";

        nativeBuildInputs = [ pkg-config ];

        buildInputs = [ gtk3 gdk-pixbuf ] ++ lib.optional withWayland gtk-layer-shell;

        buildNoDefaultFeatures = true;
        buildFeatures = [ (if withWayland then "wayland" else "x11") ];

        cargoBuildFlags = [ "--bin" "eww" ];

        cargoTestFlags = cargoBuildFlags;

        RUSTC_BOOTSTRAP = 1;

        meta = with lib; {
          description = "ElKowars wacky widgets";
          homepage = "https://github.com/elkowar/eww";
          license = licenses.mit;
          maintainers = with maintainers; [ figsoda lom ];
          mainProgram = "eww";
          broken = stdenv.isDarwin;
        };
      };

  in {
    defaultPackage.x86_64-linux = buildEww {
      rustPlatform = pkgs.rustPlatform;
      fetchFromGitHub = pkgs.fetchFromGitHub;
      pkg-config = pkgs.pkg-config;
      gtk3 = pkgs.gtk3;
      gdk-pixbuf = pkgs.gdk-pixbuf;
      gtk-layer-shell = pkgs.gtk-layer-shell;
      stdenv = pkgs.stdenv;
      lib = pkgs.lib;
    };
  };
}
