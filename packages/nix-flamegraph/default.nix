{
  writeNuApplication,
  nix,
  inferno,
  xdg-utils,
  stdenv,
}:
writeNuApplication {
  name = "nix-flamegraph";
  runtimeInputs = [
    nix
    inferno
  ]
  ++ (if stdenv.isLinux then [ xdg-utils ] else [ ]);
  text = builtins.readFile ./nix-flamegraph.nu;
}
