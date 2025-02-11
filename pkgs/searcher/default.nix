{
  writeNuApplication,
  fzf,
  jq,
  nix,
  system,
}:
writeNuApplication {
  name = "searcher";
  runtimeInputs = [
    fzf
    jq
    nix
    system
  ];
  text = # nu
    ''
      def main [...args: string] {
        mut args = $args
        mut repository = "nixpkgs"
        if ($args | length) > 1 {
          $repository = $args | first
          $args = $args | skip 1
        }
        # idk why +1
        let prefixLen = ($"* [0;1mlegacyPackages.${system}." | str length) + 1
        let len = if $repository == "nixpkgs" { $prefixLen } else { 0 }

        let selected = (
          nix search $repository ...$args
          | lines
          | filter {|| $in | str starts-with '*'}
          | str substring $len..
          | str join "\n"
          | fzf --ansi --preview="echo {1} | xargs -I {} nix eval --json nixpkgs#{}.meta | jq -C . " -d " "
        )

        if ($selected | str length) > 0 {
          let formatted = $selected | split words | first
          nix shell $"($repository)#($formatted)"
        } else {
          print "No package selected."
        }
      }
    '';
}
