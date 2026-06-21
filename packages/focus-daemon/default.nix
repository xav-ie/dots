{
  stdenv,
  swift,
}:
stdenv.mkDerivation {
  pname = "focus-daemon";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    swiftc -O focusd.swift -o focusd
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp focusd $out/bin/focusd
    runHook postInstall
  '';
  meta.mainProgram = "focusd";
}
