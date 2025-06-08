{
  writeNuApplication,
  git,
  nix,
}:
writeNuApplication {
  name = "nix-repl";
  runtimeInputs = [
    git
    nix
  ];
  text = # nu
    ''
      def git_dir [] {
        git rev-parse --show-toplevel | complete | get stdout | str trim
      }
      # Start a Nix REPL with flake context and common bindings (lib, pkgs)
      # preloaded
      def main [
        override?: string
        # Override flake path (defaults to git root, then pwd)
      ] {
        let flake_path = ($override
                          | default (git_dir)
                          | default (pwd)) | path expand

        print $"(ansi light_cyan) (ansi light_cyan_underline)($flake_path)(ansi reset)"

        nix repl --expr $"import ${./nix-repl.nix} ($flake_path)"
      }
    '';
}
