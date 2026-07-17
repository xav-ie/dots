{
  stdenv,
  swift,
}:
# Resident CoreAudio listener that makes the target device (EarPods) the default
# output the moment it appears. No entitlements/bundle/TCC needed. CoreAudio +
# Foundation auto-link on `import` under swiftc on darwin (same as focus-daemon).
stdenv.mkDerivation {
  pname = "audio-autoswitch";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    swiftc -O main.swift -o audio-autoswitch
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp audio-autoswitch $out/bin/audio-autoswitch
    runHook postInstall
  '';
  meta.mainProgram = "audio-autoswitch";
}
