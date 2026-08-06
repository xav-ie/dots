{
  stdenv,
  swift,
}:
# Yes/no NSAlert used by the lcmd-3 Zoom binding: AppleScript's `display alert`
# can't set an icon and `display dialog` looks wrong, so this is the smallest
# thing that gives a real system alert with the target app's icon.
stdenv.mkDerivation {
  pname = "confirm-open";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    mkdir -p "$out/bin"
    swiftc -O main.swift -o "$out/bin/confirm-open"
    runHook postBuild
  '';
  dontInstall = true;
  meta.mainProgram = "confirm-open";
}
