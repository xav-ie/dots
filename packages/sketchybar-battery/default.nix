{ writeNuApplication, sketchybar }:
writeNuApplication {
  name = "sketchybar-battery";
  runtimeInputs = [ sketchybar ];
  text = ./sketchybar-battery.nu |> builtins.readFile;
}
