# process-logger: samples per-process cumulative CPU time on a timer and
# records per-interval deltas to SQLite, so you can ask "what used the most CPU
# in the last hour/day?" (via `process-top`) — something btop/top can't answer.
#
# node:sqlite and node:child_process are built into Node 25, and .mts
# type-stripping runs the TypeScript directly, so the only runtime dep is `ps`,
# which sampler.mts shells out to and a systemd user service does not have.
{
  lib,
  stdenvNoCC,
  makeWrapper,
  nodejs_25,
  procps,
}:
stdenvNoCC.mkDerivation {
  pname = "process-logger";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin
    cp sampler.mts top.mts $out/lib/

    # --suffix, not --prefix: on darwin the system `ps` should still win, since
    # sampler.mts uses BSD-style `ps -axo`.
    makeWrapper ${nodejs_25}/bin/node $out/bin/process-logger \
      --suffix PATH : ${lib.makeBinPath [ procps ]} \
      --add-flags "--disable-warning=ExperimentalWarning" \
      --add-flags "$out/lib/sampler.mts"

    makeWrapper ${nodejs_25}/bin/node $out/bin/process-top \
      --add-flags "--disable-warning=ExperimentalWarning" \
      --add-flags "$out/lib/top.mts"

    runHook postInstall
  '';

  meta = {
    description = "Log per-process CPU usage over time to SQLite";
    mainProgram = "process-top";
    platforms = lib.platforms.all;
  };
}
