{ writeShellApplication }:
writeShellApplication {
  name = "is-sshed";
  runtimeInputs = [ ];
  text = ''
    who -u | grep pts >/dev/null 
  '';
}
