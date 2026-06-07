# Report-only spell-check (not a treefmt formatter, which would run typos
# --write-changes and rewrite domain terms). False positives → .typos.toml.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.typos =
        pkgs.runCommandLocal "typos-check"
          {
            nativeBuildInputs = [ pkgs.typos ];
          } # sh
          ''
            cd ${inputs.self}
            if ! typos --color always; then
              echo "Spelling issues found (above)."
              exit 1
            fi
            touch $out
          '';
    };
}
