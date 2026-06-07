# Flake-parts: lint for unannotated multiline Nix strings.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      src = inputs.self;
      lintScript = ./lint.awk;
    in
    {
      checks.nix-multiline-lint =
        pkgs.runCommandLocal "nix-multiline-lint"
          {
            nativeBuildInputs = [ pkgs.gawk ];
          } # sh
          ''
            matches=$(find ${src} -name '*.nix' -exec awk -v min_lines=5 -f ${lintScript} {} + 2>&1 \
              | sed 's|${src}/||' || true)
            if [ -n "$matches" ]; then
              echo "Files with unannotated inline string blocks of 5+ lines:"
              echo "$matches"
              echo ""
              echo "Please annotate your code blocks."
              exit 1
            fi
            touch $out
          '';
    };
}
