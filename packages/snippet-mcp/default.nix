{
  lib,
  rustPlatform,
  cmake,
  pkg-config,
}:
rustPlatform.buildRustPackage {
  pname = "snippet-mcp";
  version = "0.1.0";

  src = lib.cleanSourceWith {
    src = ./.;
    # Drop the Nix file itself, build outputs, and editor cruft so they don't
    # invalidate the source hash.
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

  # aws-lc-rs (pulled by reqwest's `rustls` feature) needs cmake and a C
  # toolchain at build time. pkg-config is harmless and lets it discover
  # system libraries if it ever falls back.
  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  # aws-lc-rs's build script invokes cmake which expects to manage its own
  # build dir; the standard nix cmake hook gets in the way.
  dontUseCmakeConfigure = true;

  # The HTTP integration is exercised by scripts/smoke.sh against a live
  # binary; cargo's unit tests are empty. Skip checkPhase to keep builds fast.
  doCheck = false;

  postInstall = ''
    mkdir -p $out/share/snippet-mcp
    cp -R seeds $out/share/snippet-mcp/seeds
  '';

  meta = {
    description = "MCP server exposing markdown snippets as searchable tools for executor.";
    homepage = "https://github.com/RhysSullivan/executor";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "snippet-mcp";
  };
}
