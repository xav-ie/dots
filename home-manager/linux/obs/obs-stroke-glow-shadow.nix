{
  lib,
  stdenv,
  fetchFromGitHub,
  obs-studio,
  cmake,
  ...
}:

stdenv.mkDerivation rec {
  pname = "obs-stoke-glow-shadow";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "FiniteSingularity";
    repo = "obs-stroke-glow-shadow";
    rev = "refs/tags/v${version}";
    hash = "sha256-aYt3miY71aikIq0SqHXglC/c/tI8yGkIo1i1wXxiTek=";
  };

  buildInputs = [
    obs-studio
  ];

  nativeBuildInputs = [
    cmake
  ];

  cmakeFlags = [
    "-DCMAKE_C_FLAGS=-Wno-error=stringop-overflow"
  ];
  # TODO: which is better? ^v
  # NIX_CFLAGS_COMPILE = "-Wno-error=stringop-overflow";

  postInstall = ''
    rm -rf "$out/share"
    mkdir -p "$out/share/obs"
    mv "$out/data/obs-plugins" "$out/share/obs"
    rm -rf "$out/obs-plugins" "$out/data"
  '';

  meta = with lib; {
    description = "An OBS plugin to provide efficient Stroke, Glow, and Shadow effects on masked sources.";
    homepage = "https://github.com/FiniteSingularity/obs-stroke-glow-shadow";
    license = licenses.gpl2Only;
    # TODO: add to nixpkgs!
    # maintainers = with maintainers; [ XavierRuiz ];
    mainProgram = "obs-stroke-glow-shadow";
    platforms = platforms.linux;
  };
}
