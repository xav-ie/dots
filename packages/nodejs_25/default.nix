# Prebuilt Node.js 25 binary — Hydra hasn't cached nodejs_25 yet so nixpkgs
# builds from source (~2 h).  Remove once nodejs_25 appears in cache.nixos.org.
{
  lib,
  stdenv,
  fetchurl,
  makeBinaryWrapper,
  autoPatchelfHook,
}:
let
  version = "25.9.0";
  platformMap = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-Fe7rA8YGkaR2Tv+mzukgIX9yBYpwvP/l9MEgm75K1aM=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-HY231uKR0WfoxGeuQJS+F14aCzlpx64fiVW594JPey4=";
    };
  };
  info =
    platformMap.${stdenv.hostPlatform.system}
      or (throw "nodejs_25: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation {
  pname = "nodejs";
  inherit version;
  src = fetchurl {
    url = "https://nodejs.org/dist/v${version}/node-v${version}-${info.platform}.tar.xz";
    inherit (info) hash;
  };
  nativeBuildInputs = [
    makeBinaryWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];
  dontBuild = true;
  dontStrip = true;
  installPhase = ''
    mkdir -p $out
    cp -r ./* $out/

    # The official binary tries to open /System/Library/OpenSSL/openssl.cnf
    # which the Nix sandbox blocks.  Point it at an empty config instead.
    wrapProgram $out/bin/node --set OPENSSL_CONF "/dev/null"
  '';
  meta = {
    description = "Prebuilt Node.js 25 binary from nodejs.org";
    homepage = "https://nodejs.org";
    license = lib.licenses.mit;
    platforms = platformMap |> builtins.attrNames;
  };
}
