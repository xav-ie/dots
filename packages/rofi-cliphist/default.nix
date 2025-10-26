{
  writeNuApplication,
  rofi,
  cliphist,
  wl-clipboard,
  coreutils,
}:
let
  rofi-cliphist-helper = writeNuApplication {
    name = "rofi-cliphist-helper";
    runtimeInputs = [
      cliphist
      wl-clipboard
      coreutils
    ];
    text = builtins.readFile ./rofi-cliphist-helper.nu;
  };

  rofi-cliphist-images-helper = writeNuApplication {
    name = "rofi-cliphist-images-helper";
    runtimeInputs = [
      cliphist
      wl-clipboard
      coreutils
    ];
    text = builtins.readFile ./rofi-cliphist-images-helper.nu;
  };
in
writeNuApplication {
  name = "rofi-cliphist";
  runtimeInputs = [
    rofi
    rofi-cliphist-helper
    rofi-cliphist-images-helper
  ];
  text = builtins.readFile ./rofi-cliphist.nu;
}
