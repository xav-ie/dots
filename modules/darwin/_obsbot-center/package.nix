# OBSBOT Center, the control app for OBSBOT webcams. The CDN only serves the DMG
# behind a short-lived signed path, which obsbot.com gets from an unauthenticated
# endpoint when you click Download, so the fixed-output fetch asks for one first.
{
  cacert,
  curl,
  jq,
  stdenvNoCC,
  undmg,
}:
let
  version = "2.0.16.433";
  dmg = stdenvNoCC.mkDerivation {
    name = "obsbot-center-${version}.dmg";
    nativeBuildInputs = [
      curl
      jq
    ];
    url = "https://resource-cdn.obsbothk.com/download/common/Obsbot_Center_OA_E_MacOS_Apple_${version}_release.dmg";
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    buildCommand = ''
      signed=$(jq -n --arg url "$url" '{ $url }' \
        | curl -fsS -X POST -H 'content-type: application/json' --data @- \
          https://remo-api.obsbot.com/fms/v1/files/cdn/authorization \
        | jq -r .url)
      curl -fsSL --retry 3 -o "$out" "$signed"
    '';
    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = "sha256-lmKdt5Pxk3xKFcnRnKVLO1/agVQE6fD6gciSqaX92oE=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "obsbot-center";
  inherit version;
  src = dmg;
  nativeBuildInputs = [ undmg ];
  sourceRoot = "OBSBOT_Center.app";
  # The bundle keeps OBSBOT's Developer ID signature; fixup would invalidate it.
  dontFixup = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications/OBSBOT_Center.app"
    cp -R . "$out/Applications/OBSBOT_Center.app"
    runHook postInstall
  '';
  meta.platforms = [ "aarch64-darwin" ];
}
