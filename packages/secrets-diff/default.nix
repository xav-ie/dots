{
  pkgs ? import <nixpkgs> { },
}:
pkgs.writeShellApplication {
  name = "secrets-diff";
  runtimeInputs = [
    pkgs.age
    pkgs.git
    pkgs.sops
  ];
  text = builtins.readFile ./secrets-diff.sh;
}
