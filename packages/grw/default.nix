{
  browse,
  gh,
  writeNuApplication,
}:
writeNuApplication {
  name = "grw";
  runtimeInputs = [
    browse
    gh
  ];
  text = # nu
    ''
      # Open this repo in my browser (herdr-aware, unlike `gh -w` which would
      # open on the desktop when attached remotely).
      def --wrapped main [...args] {
        browse (^gh repo view --json url -q .url ...$args | str trim)
      }
    '';
}
