# Proton Drive CLI — official prebuilt binary.
#
# Not in nixpkgs. Upstream (github.com/ProtonDriveApps/sdk, `cli/`) is TypeScript
# bundled into a standalone Bun executable; building it needs `bun install`
# against a lockfile, so we take Proton's own release binary instead.
#
# Bump `version` + both hashes from https://proton.me/download/drive/cli/index.html
# (that page also publishes SHA-512s to cross-check against).
#
# Sessions live in the OS secret store, so on Linux this needs a running
# secret-service (modules/nixos/keyring.nix enables gnome-keyring).
{
  lib,
  stdenv,
  autoPatchelfHook,
  fetchurl,
  libsecret,
  patchelf,
}:
let
  version = "0.7.0";
  targets = {
    "x86_64-linux" = {
      suffix = "linux-x64";
      hash = "sha256-Tjx0p6JdoA16DKnuIjqbewsjjaNXq2/P7gSlwxPd9NE=";
    };
    "aarch64-darwin" = {
      suffix = "darwin-arm64";
      hash = "sha256-uTHY1ePqcrjcoUM/b+uQ/6ACQw1p+1gZZH5JpbmdyBQ=";
    };
  };
  target =
    targets.${stdenv.hostPlatform.system}
      or (throw "proton-drive-cli: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "proton-drive-cli";
  inherit version;

  src = fetchurl {
    url = "https://proton.me/download/drive/cli/${version}/${target.suffix}/proton-drive";
    inherit (target) hash;
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    autoPatchelfHook
    patchelf
  ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libsecret
    stdenv.cc.cc.lib
  ];

  # libsecret-1.so.0 is dlopen'd by soname, so autoPatchelf never sees it. Make it
  # a real DT_NEEDED before autoPatchelf runs and the RUNPATH gets filled in too.
  preFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf --add-needed libsecret-1.so.0 $out/bin/proton-drive
  '';

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true; # Bun embeds its runtime; stripping breaks the binary

  installPhase = ''
    runHook preInstall
    install -Dm755 $src $out/bin/proton-drive
    runHook postInstall
  '';

  meta = {
    description = "Command-line interface for Proton Drive";
    homepage = "https://github.com/ProtonDriveApps/sdk/blob/main/cli/README.md";
    license = lib.licenses.mit;
    mainProgram = "proton-drive";
    platforms = builtins.attrNames targets;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
