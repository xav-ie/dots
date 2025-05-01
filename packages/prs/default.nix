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
  text = builtins.readFile ./prs.nu;
}
