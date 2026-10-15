# based on:
# https://github.com/thefiredman/nix/blob/3c11cbaa7d74c9308f1f10dcbab8d7317d96ee84/packages/apple-emoji-linux.nix
# "Reference as you like" license
{
  fetchurl,
  lib,
  stdenvNoCC,
}:
let
  version = "macos-26-20260722-484daf4e";
in
stdenvNoCC.mkDerivation {
  pname = "apple-emoji-linux";
  dontUnpack = true;
  inherit version;

  src = fetchurl {
    url = "https://github.com/samuelngs/apple-emoji-linux/releases/download/${version}/AppleColorEmoji-Linux.ttf";
    sha256 = "sha256-43x69iZaxKCvbVe8ZehhCad22ZZug0MzRVf2PaSCUW8=";
  };

  installPhase = ''
    # Explicit name: `-t` would keep the source's hash-prefixed store name,
    # which reads as a reference and keeps the 111 MiB download in the closure.
    install -Dm644 $src $out/share/fonts/truetype/AppleColorEmoji-Linux.ttf
  '';

  meta = with lib; {
    description = "Apple Color Emoji for Linux";
    longDescription = "AppleColorEmoji-Linux.ttf from Samuel Ng's apple-emoji-linux, release version ${version}, packaged for Nix.";
    homepage = "https://github.com/samuelngs/apple-emoji-linux";
    license = licenses.wtfpl;
    platforms = platforms.unix;
  };
}
