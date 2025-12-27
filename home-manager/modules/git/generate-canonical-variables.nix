# Run: cat $(nix-build generate-canonical-variables.nix) > canonical-variables-generated.nix
{
  pkgs ? import <nixpkgs> { },
}:

pkgs.runCommand "canonical-variables-generated.nix" { nativeBuildInputs = [ pkgs.git ]; } ''
  {
    echo "# Auto-generated from git ${pkgs.git.version}. Maps section.lowercasevar -> canonicalVar"
    echo "{"
    git help --config | awk -F. '
      NF==2 && tolower($2) != $2 {
        section = tolower($1)
        sections[section] = sections[section] sprintf("    %s = \"%s\";\n", tolower($2), $2)
      }
      END {
        for (s in sections) {
          printf "  %s = {\n%s  };\n", s, sections[s]
        }
      }
    '
    echo "}"
  } > $out
''
