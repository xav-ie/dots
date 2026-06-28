{
  stdenv,
  rustc,
}:
# move-pip is a tiny native (Rust) client so skhd's per-keypress spawn (~60/s
# while holding grow/shrink) is cheap: just this binary, no bash wrapper. The
# Firefox fast path (loopback socket to the firefox.cfg listener) is handled in
# Rust; only the Chromium/iPhone-Mirroring fallback shells out to osascript
# (move-pip.js). No crates beyond std, so a single `rustc` invocation suffices.
stdenv.mkDerivation {
  pname = "move-pip";
  version = "0.2.0";
  src = ./.;
  nativeBuildInputs = [ rustc ];
  buildPhase = ''
    runHook preBuild
    mkdir -p "$out/bin" "$out/libexec"
    cp move-pip.js "$out/libexec/move-pip.js"
    substitute move-pip.rs move-pip.gen.rs \
      --subst-var-by JS_PATH "$out/libexec/move-pip.js"
    rustc -O --edition 2021 --crate-name move_pip move-pip.gen.rs -o "$out/bin/move-pip"
    runHook postBuild
  '';
  dontInstall = true;
}
