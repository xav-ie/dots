{ writeShellApplication, uair }:
writeShellApplication {
  name = "uair-toggle";
  runtimeInputs = [ uair ];
  text = ''
    uairctl toggle || { nohup uair > /dev/null 2>&1 & disown; sleep 2 && uairctl toggle; }
  '';
}
