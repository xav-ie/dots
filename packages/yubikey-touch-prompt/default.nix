{
  stdenv,
  swift,
}:
# Floating "Touch your YubiKey" panel while the YubiKey waits for a touch, so a
# sudo on praesidium (via the forwarded agent) doesn't rely on noticing the
# blink. Run as a launchd agent by modules/home-darwin/yubikey-touch-prompt.nix.
stdenv.mkDerivation {
  pname = "yubikey-touch-prompt";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    mkdir -p "$out/bin"
    swiftc -O main.swift -o "$out/bin/yubikey-touch-prompt"
    runHook postBuild
  '';
  dontInstall = true;
  meta.mainProgram = "yubikey-touch-prompt";
}
