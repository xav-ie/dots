# based on:
# https://github.com/thefiredman/nix/blob/3c11cbaa7d74c9308f1f10dcbab8d7317d96ee84/packages/apple-emoji-linux.nix
# "Reference as you like" license
{
  fetchurl,
  lib,
  stdenvNoCC,
}:
let
  version = "v17.4";
in
stdenvNoCC.mkDerivation {
  pname = "apple-emoji-linux";
  dontUnpack = true;
  inherit version;

  src = fetchurl {
    url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/${version}/AppleColorEmoji.ttf";
    sha256 = "sha256-SG3JQLybhY/fMX+XqmB/BKhQSBB0N1VRqa+H6laVUPE=";
  };

  installPhase = ''
    install -Dm644 $src -t $out/share/fonts/truetype
  '';

  meta = with lib; {
    description = "Apple Color Emoji for Linux";
    longDescription = "AppleColorEmoji.ttf from Samuel Ng's apple-emoji-linux, release version ${version}, packaged for Nix.";
    homepage = "https://github.com/samuelngs/apple-emoji-linux";
    license = licenses.wtfpl;
    platforms = platforms.unix;
  };
}
