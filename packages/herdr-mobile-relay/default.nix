# Phone control surface for the herd. Upstream installs it as a herdr plugin
# whose wizard stands up its own Cloudflare tunnel; this packages the release
# instead, configured by env in modules/herdr-mobile-relay.nix.
{
  fetchurl,
  stdenvNoCC,
}:
let
  version = "0.18.3";
in
stdenvNoCC.mkDerivation {
  pname = "herdr-mobile-relay";
  inherit version;

  src = fetchurl {
    url = "https://github.com/0cv/herdr-mobile-relay/releases/download/v${version}/herdr-mobile-relay_${version}_linux_amd64.tar.gz";
    hash = "sha256-HQWlWOBNls/we+wJz9adrkUSy7d2pvX+Zt2BuO7ZMOo=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 herdr-mobile-relay $out/bin/herdr-mobile-relay

    # The phone app served at `/`; without it pages 404 while /healthz and /ws
    # still answer. HERDR_WEB_ROOT points here.
    mkdir -p $out/share/herdr-mobile-relay
    cp -r web $out/share/herdr-mobile-relay/web

    runHook postInstall
  '';

  passthru.webRoot = "share/herdr-mobile-relay/web";

  meta = {
    description = "Control herdr agents from your phone";
    homepage = "https://github.com/0cv/herdr-mobile-relay";
    mainProgram = "herdr-mobile-relay";
    platforms = [ "x86_64-linux" ];
  };
}
