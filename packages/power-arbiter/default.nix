{
  lib,
  rustPlatform,
}:
rustPlatform.buildRustPackage {
  pname = "power-arbiter";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    # Drop the Nix file, build outputs, and editor cruft so they don't
    # invalidate the source hash.
    filter =
      path: _type:
      let
        base = baseNameOf path;
      in
      !(base == "default.nix" || base == "target" || base == "result" || base == ".direnv");
  };

  cargoLock.lockFile = ./Cargo.lock;

  # std-only binary; the cargo unit tests are empty.
  doCheck = false;

  meta = {
    description = "Demand-driven CPU/GPU power arbiter (ssh/seat/http) for praesidium.";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "power-arbiter";
  };
}
