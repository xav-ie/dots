# Flake-parts module: spell-check sources as a REPORT-ONLY flake check.
# Deliberately NOT a treefmt formatter — treefmt runs typos with
# `--write-changes`, which silently rewrites code (it "corrects" domain terms
# like rela_path, hass, and intentional git typo-aliases). Here typos only
# reports and fails the check; it never edits a file. Fix findings by hand, or
# add false positives to .typos.toml at the repo root.
{
  perSystem =
    { pkgs, ... }:
    let
      src = ../..;
    in
    {
      checks.typos =
        pkgs.runCommandLocal "typos-check"
          {
            nativeBuildInputs = [ pkgs.typos ];
          } # sh
          ''
            cd ${src}
            if ! typos --color always; then
              echo "Spelling issues found (above)."
              exit 1
            fi
            touch $out
          '';
    };
}
