{
  lib,
  rustPlatform,
  src,
}:
rustPlatform.buildRustPackage {
  pname = "zerobrew";
  version = src.shortRev or src.rev or "unstable";

  inherit src;

  cargoHash = "sha256-k336DgCppGWDA+8CoYd+CC/rDkP/DpJBoGQkmQHLsnw=";

  # Skip tests that require network access (mock servers, HTTP requests)
  checkFlags = [
    "--skip=api::tests::"
    "--skip=download::tests::"
    "--skip=install::tests::"
  ];

  meta = with lib; {
    description = "A drop-in, 5-20x faster, experimental Homebrew alternative";
    homepage = "https://github.com/lucasgelfond/zerobrew";
    license = with licenses; [
      asl20
      mit
    ];
    maintainers = [ ];
    platforms = platforms.darwin;
    mainProgram = "zb";
  };
}
