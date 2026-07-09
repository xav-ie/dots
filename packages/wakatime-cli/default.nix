# WakaTime CLI, pinned.
#
# The Claude Code plugin (and the vim/VS Code extensions) shell out to a
# `wakatime-cli` binary. Left to themselves they download it into ~/.wakatime and
# self-update on a throttle — a mutable, un-pinned blob. The plugin checks
# `which wakatime-cli` first, though, and treats a binary found on PATH as always
# current, so providing it here (via home.packages in modules/wakatime.nix) keeps
# the CLI pinned and stops the self-download entirely.
#
# nixpkgs' wakatime-cli is stuck on the 1.x line, which predates
# `--sync-ai-activity` (the flag the Claude plugin needs), so we fetch WakaTime's
# official prebuilt release — a static Go binary that runs on NixOS as-is (no
# patchelf). Bump `version` + both hashes together from the GitHub releases.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
}:
let
  version = "2.21.4";
  targets = {
    "x86_64-linux" = {
      suffix = "linux-amd64";
      hash = "sha256-BZ7QyVLJJ0qP+Bbmw4hv4ENVP74QCESX2fCkAzyPWpM=";
    };
    "aarch64-darwin" = {
      suffix = "darwin-arm64";
      hash = "sha256-qimZtrkV/UWQHalfaphaT/PKKCzM+tla/vP+9g6huik=";
    };
  };
  target =
    targets.${stdenv.hostPlatform.system}
      or (throw "wakatime-cli: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "wakatime-cli";
  inherit version;

  src = fetchurl {
    url = "https://github.com/wakatime/wakatime-cli/releases/download/v${version}/wakatime-cli-${target.suffix}.zip";
    inherit (target) hash;
  };

  nativeBuildInputs = [ unzip ];

  # fetchurl leaves a bare zip; unzip drops the single binary in place.
  unpackPhase = ''
    runHook preUnpack
    unzip $src
    runHook postUnpack
  '';

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true; # already stripped, static Go binary

  installPhase = ''
    runHook preInstall
    install -Dm755 wakatime-cli-${target.suffix} $out/bin/wakatime-cli
    runHook postInstall
  '';

  meta = {
    description = "Command line interface for WakaTime";
    homepage = "https://github.com/wakatime/wakatime-cli";
    license = lib.licenses.bsd3;
    mainProgram = "wakatime-cli";
    platforms = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
