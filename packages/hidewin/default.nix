{
  stdenv,
  swift,
}:
# hidewin — CLI to toggle capture-hidden apps on demand. The actual hiding is
# done by the injected agent in modules/darwin/_dyld-inject/hide-windows (which
# runs inside each app and sets NSWindowSharingNone — a cross-process set
# silently no-ops, verified). This CLI just posts a distributed notification the
# agent observes: `hidewin show|hide <bundle-id>|--all`. Foundation auto-links.
stdenv.mkDerivation {
  pname = "hidewin";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ swift ];
  buildPhase = ''
    runHook preBuild
    mkdir -p "$out/bin"
    swiftc -O main.swift -o "$out/bin/hidewin"
    runHook postBuild
  '';
  dontInstall = true;
  meta.mainProgram = "hidewin";
}
