{
  browse,
  gh,
  writeNuApplication,
}:
writeNuApplication {
  name = "gpw";
  runtimeInputs = [
    browse
    gh
  ];
  text = # nu
    ''
      # Open the current branch's PR in my browser (herdr-aware, unlike `gh -w`
      # which would open on the desktop when attached remotely).
      def --wrapped main [...args] {
        browse (^gh pr view --json url -q .url ...$args | str trim)
      }
    '';
}
