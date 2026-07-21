{
  writeNuApplication,
  fzf,
  gh,
  git,
}:
writeNuApplication {
  name = "git-prs";
  runtimeInputs = [
    fzf
    gh
    git
  ];
  text = ./git-prs.nu |> builtins.readFile;
}
