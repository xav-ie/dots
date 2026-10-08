{
  lib,
  stdenv,
  fetchFromGitHub,
  obs-studio,
  cmake,
  ...
}:

stdenv.mkDerivation rec {
  pname = "obs-advanced-masks";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "FiniteSingularity";
    repo = "obs-advanced-masks";
    rev = "refs/tags/v${version}";
    hash = "sha256-NtmOWKk3eZeRa3TvclZpg4sj8lbOoY8hUhxs1z6kEW4=";
  };

  buildInputs = [
    obs-studio
  ];

  nativeBuildInputs = [
    cmake
  ];

  # 1.1.0 drops a `const` qualifier in obs-utils.c and builds with -Werror.
  # gcc 14 only warned; gcc 16 promoted discarded-qualifiers to an error.
  env.NIX_CFLAGS_COMPILE = "-Wno-error=discarded-qualifiers";

  postInstall = ''
    rm -rf "$out/share"
    mkdir -p "$out/share/obs"
    mv "$out/data/obs-plugins" "$out/share/obs"
    rm -rf "$out/obs-plugins" "$out/data"
  '';

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
