{ writeShellApplication, bubblewrap }:
writeShellApplication {
  name = "claude-yolo";
  runtimeInputs = [ bubblewrap ];
  text = ./claude-yolo.sh |> builtins.readFile;
}
