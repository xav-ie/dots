{
  lib,
  stdenv,
  fetchurl,
  unzip,
  autoPatchelfHook,
  glib,
  nspr,
  nss,
  atk,
  at-spi2-atk,
  at-spi2-core,
  dbus,
  expat,
  libxkbcommon,
  alsa-lib,
  mesa,
  systemdLibs,
  xorg,
}:
let
  version = "146.0.7680.31";
in
stdenv.mkDerivation {
  pname = "chrome-headless-shell";
  inherit version;

  src = fetchurl {
    url = "https://storage.googleapis.com/chrome-for-testing-public/${version}/linux64/chrome-headless-shell-linux64.zip";
    hash = "sha256-26ioTx8Ps1Vmz1jbMcLWzQO7wYTXC326Ec4D2/hFWFg=";
  };

  nativeBuildInputs = [ unzip autoPatchelfHook ];

  # fetchurl doesn't know how to unpack zips by default.
  unpackPhase = ''
    unzip $src
    sourceRoot=chrome-headless-shell-linux64
  '';

  dontBuild = true;
  dontStrip = true;

  # Runtime libraries needed by the prebuilt binary (same deps as chromium).
  buildInputs = [
    glib
    nspr
    nss
    atk
    at-spi2-atk
    at-spi2-core
    dbus
    expat
    libxkbcommon
    alsa-lib
    mesa
    systemdLibs
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
    xorg.libxcb
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/chrome-headless-shell $out/bin
    cp -r ./* $out/lib/chrome-headless-shell/
    ln -s $out/lib/chrome-headless-shell/chrome-headless-shell $out/bin/chrome-headless-shell
    runHook postInstall
  '';

  meta = with lib; {
    description = "Headless shell for Chrome (old headless mode as standalone binary)";
    homepage = "https://developer.chrome.com/blog/chrome-headless-shell";
    license = licenses.bsd3;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "chrome-headless-shell";
  };
}
