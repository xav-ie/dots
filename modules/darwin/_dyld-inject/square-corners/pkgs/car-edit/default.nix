{
  lib,
  stdenvNoCC,
}:
let
  # Xcode's toolchain has to win over nix for `swift`. Kept scoped to the two
  # swift calls rather than exported: an exported PATH survives into
  # fixupPhase, where /usr/bin's BSD find shadows nix's and the
  # make-symlinks-relative and strip hooks fail on GNU `find -printf`.
  swiftPath = "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:$PATH";
in
stdenvNoCC.mkDerivation {
  pname = "car-edit";
  version = "0.1.0";

  src =
    with lib.fileset;
    toSource {
      root = ./.;
      fileset =
        unions [
          (maybeMissing ./.build)
          ./default.nix
        ]
        |> difference ./.;
    };

  # Apple Swift 6.3 (Xcode 26) refuses Nix's apple-sdk-14.4 (Swift 5.10
  # module interfaces). Reaching into /Applications/Xcode.app for the matched
  # toolchain is the practical option until we rewrite this in Obj-C against
  # apple-sdk. The user has sandbox = "relaxed" so __noChroot is honored.
  __noChroot = true;

  buildPhase = ''
    runHook preBuild

    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    export SDKROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

    PATH="${swiftPath}" swift build -c release --disable-sandbox

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    bin_path=$(PATH="${swiftPath}" swift build -c release --disable-sandbox --show-bin-path)
    cp "$bin_path/car-edit" "$out/bin/car-edit"
    chmod 755 "$out/bin/car-edit"
    runHook postInstall
  '';

  meta = {
    description = "CLI for replacing WindowShapeEdges renditions in macOS .car asset catalogs";
    platforms = lib.platforms.darwin;
  };
}
