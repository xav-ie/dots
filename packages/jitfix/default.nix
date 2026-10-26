# libjitfix.dylib: every arm64 JDK >= 21 SIGBUSes at startup on nox
# (CodeHeap::allocate), because with SIP off and amfi_get_out_of_my_way dyld's
# hardware TPRO toggle resets the thread's JIT write state. This interposes the
# dl* calls HotSpot makes and restores write mode afterwards. Inject it only
# into the JVMs that need it (DYLD_INSERT_LIBRARIES), never globally.
{
  lib,
  stdenv,
  fetchFromGitHub,
}:
stdenv.mkDerivation {
  pname = "jitfix";
  version = "0-unstable-2026-09-29";

  src = fetchFromGitHub {
    owner = "dazi2011";
    repo = "macos-java-sigbus-codeheap-allocate-fix";
    rev = "015ad917443c71b8c89c0ed1418e551dd2970e99";
    hash = "sha256-jp5mqyFMsQC72ZKbBM0HtyTmllR94Qgshspoex2Gc4Q=";
  };

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -dynamiclib -o libjitfix.dylib jitfix.c
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm444 libjitfix.dylib $out/lib/libjitfix.dylib
    runHook postInstall
  '';

  meta = {
    description = "Workaround for HotSpot SIGBUS in CodeHeap::allocate on Apple Silicon with dyld TPRO";
    homepage = "https://github.com/dazi2011/macos-java-sigbus-codeheap-allocate-fix";
    license = lib.licenses.mit;
    platforms = [ "aarch64-darwin" ];
  };
}
