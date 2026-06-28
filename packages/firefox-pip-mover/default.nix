{
  stdenvNoCC,
  esbuild,
}:
# Bundle the TypeScript PiP mover into a single chrome subscript (pip-mover.js),
# which firefox.cfg loads via Services.scriptloader.loadSubScript. esbuild only
# strips types + bundles (no type-checking — that's `npm run typecheck` / tests
# in the devShell), so the build needs no node_modules and stays reproducible.
#
# Output is $out/pip-mover.js; modules/home-darwin/firefox symlinks it next to
# firefox.cfg in Firefox.app's Resources dir.
stdenvNoCC.mkDerivation {
  pname = "firefox-pip-mover";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ esbuild ];
  buildPhase = ''
    runHook preBuild
    esbuild src/main.ts \
      --bundle \
      --format=iife \
      --platform=neutral \
      --target=es2020 \
      --legal-comments=none \
      --outfile=pip-mover.js
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp pip-mover.js "$out/pip-mover.js"
    runHook postInstall
  '';
  doCheck = false;
}
