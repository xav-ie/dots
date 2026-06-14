{
  writeNuApplication,
  fzf,
  gh,
  git,
}:
writeNuApplication {
  name = "prs";
  runtimeInputs = [
    fzf
    gh
    git
  ];
  text = ./prs.nu |> builtins.readFile;
}
