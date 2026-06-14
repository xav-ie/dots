{
  lib,
  rustPlatform,
  cmake,
  pkg-config,
}:
rustPlatform.buildRustPackage {
  pname = "browser-session-mcp";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: _type:
      let
        base = baseNameOf path;
      in
      !(
        base == "default.nix"
        || base == "target"
        || base == "result"
        || base == ".direnv"
        || (base |> lib.hasSuffix ".log")
      );
  };

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  # aws-lc-rs (pulled by reqwest's rustls-tls feature) needs cmake and a C
  # toolchain at build time.
  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  # aws-lc-rs's build script invokes cmake which expects to manage its own
  # build dir; nixpkgs' default cmake hook gets in the way.
  dontUseCmakeConfigure = true;

  doCheck = false;

  meta = {
    description = "MCP server giving each caller an isolated browser session against a shared persistent Chrome.";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "browser-session-mcp";
  };
}
