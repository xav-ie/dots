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
in
writeNuApplication {
  name = "rofi-cliphist";
  runtimeInputs = [
    rofi
    rofi-cliphist-helper
  ];
  text = builtins.readFile ./rofi-cliphist.nu;
}
