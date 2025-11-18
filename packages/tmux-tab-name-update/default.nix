{ pkgsStatic }:
pkgsStatic.stdenv.mkDerivation {
  pname = "tmux-tab-name-update";
  version = "0.1.0";

  src = ./tmux-tab-name-update.c;

  dontUnpack = true;

  buildPhase =
    if pkgsStatic.stdenv.isDarwin then
      # macOS doesn't support fully static linking
      ''
        $CC -Os -fomit-frame-pointer -fno-asynchronous-unwind-tables \
          -fno-stack-protector -dead_strip -o tmux-tab-name-update $src
      ''
    else
      # Linux static build
      ''
        $CC -Os -fomit-frame-pointer -fno-asynchronous-unwind-tables \
          -fno-stack-protector -ffunction-sections -fdata-sections \
          -Wl,--gc-sections -static -s -o tmux-tab-name-update $src
      '';

  installPhase = ''
    mkdir -p $out/bin
    cp tmux-tab-name-update $out/bin/
  '';
}
