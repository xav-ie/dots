{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "sketchybar-hover";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: type:
      let
        base = baseNameOf path;
      in
      !(type == "regular" && (base == "default.nix" || (base |> lib.hasSuffix ".nix")));
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  meta = with lib; {
    description = "Persistent hover-state daemon for SketchyBar (replaces nu fork-storm)";
    license = licenses.mit;
    platforms = platforms.darwin;
    mainProgram = "sketchybar-hover";
  };
}
