{
  gh,
  update-pr,
  writeNuApplication,
}:
writeNuApplication {
  name = "gp";
  runtimeInputs = [
    gh
    update-pr
  ];
  text = # nu
    ''
      # Create a PR with body based on commits and branch title
      def --wrapped main [...args] {
        ^gh pr create --body "" --title (^git branch --show-current) ...$args;
        update-pr
      }
    '';
}
