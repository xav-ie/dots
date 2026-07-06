{
  lib,
  pkgs-bleeding,
}:
pkgs-bleeding.rustPlatform.buildRustPackage {
  pname = "nu_plugin_prompt";
  version = "0.0.1";

  src = lib.cleanSource ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  passthru.clippy = pkgs-bleeding.clippy;

  meta = {
    description = "Nushell plugin that renders the prompt in-process";
    mainProgram = "nu_plugin_prompt";
  };
}
