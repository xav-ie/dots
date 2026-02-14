{ writeShellApplication, bubblewrap }:
writeShellApplication {
  name = "claude-yolo";
  runtimeInputs = [ bubblewrap ];
  text = builtins.readFile ./claude-yolo.sh;
}
