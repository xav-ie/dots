{
  lib,
  pkgs-bleeding,
}:
# nu-plugin 0.112 needs rustc >= 1.92.  Use the bleeding-edge rustPlatform
# (1.94+) instead of the default (1.91).
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
