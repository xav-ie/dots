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
  ++ (if stdenv.hostPlatform.isLinux then [ xdg-utils ] else [ ]);
  text = ./nix-flamegraph.nu |> builtins.readFile;
}
