{ writeNuApplication, sketchybar }:
writeNuApplication {
  name = "sketchybar-battery";
  runtimeInputs = [ sketchybar ];
  text = builtins.readFile ./sketchybar-battery.nu;
}
