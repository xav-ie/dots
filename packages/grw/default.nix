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
        let url = (^gh repo view --json url -q .url ...$args | str trim)
        if ($url | is-empty) { exit 1 }
        browse $url
      }
    '';
}
