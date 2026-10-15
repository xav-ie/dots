{
  lib,
  stdenv,
  fetchFromGitHub,
  obs-studio,
  cmake,
  curl,
  nlohmann_json,
  qt6,
  ...
}:

stdenv.mkDerivation rec {
  pname = "obs-advanced-masks";
  version = "1.6.0";

  src = fetchFromGitHub {
    owner = "FiniteSingularity";
    repo = "obs-advanced-masks";
    rev = "refs/tags/v${version}";
    hash = "sha256-Vnlq9OQc8mfuhn0O9oI+Y3+Yh2tP0DvrPFfLw1fypz8=";
  };

  buildInputs = [
    curl
    obs-studio
    qt6.qtbase
    qt6.qtsvg
  ];

  nativeBuildInputs = [
    cmake
  ];

  # CMakeLists FetchContent-downloads nlohmann/json at configure time; hand it
  # the source tree instead.
  # The font-awesome mask picker is a Qt dialog, so the release presets build
  # with ENABLE_FRONTEND_API + ENABLE_QT; the plain CMake defaults leave them off.
  cmakeFlags = [
    "-DENABLE_FRONTEND_API=ON"
    "-DENABLE_QT=ON"
    "-DFETCHCONTENT_SOURCE_DIR_JSON=${nlohmann_json.src}"
  ];

  dontWrapQtApps = true;

  meta = with lib; {
    description = "Advanced Masking Plugin for OBS";
    homepage = "https://github.com/FiniteSingularity/obs-advanced-masks";
    license = licenses.gpl2Only;
    # TODO: add to nixpkgs!
    # maintainers = with maintainers; [ XavierRuiz ];
    mainProgram = "obs-advanced-masks";
    platforms = platforms.linux;
  };
}
