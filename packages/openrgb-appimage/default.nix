{
  appimageTools,
  fetchurl,
  system,
}:
let
  pname = "openrgb";
  release = "0.9";
  releaseCommit = "b5f46e3";
  arch = builtins.elemAt (builtins.split "-" system) 0;
  version = builtins.concatStringsSep "_" [
    release
    arch
    releaseCommit
  ];

  src = fetchurl {
    url = "https://openrgb.org/releases/release_${release}/OpenRGB_${version}.AppImage";
    hash = "sha256-tVMBABLTo03AtXDhE410ZvAPCIFYzPn1SaUtiNYbHsA=";
  };
in
appimageTools.wrapType2 {
  inherit pname version src;
}
