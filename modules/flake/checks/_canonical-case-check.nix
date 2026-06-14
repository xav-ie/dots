# Checks that git config uses canonical casing:
# - Sections should be lowercase (subsections are case-sensitive, left unchanged)
# - Variables should use camelCase per git documentation
#
# This module exports check results for use by flake checks.
# Run `nix flake check` or `just check` to validate git config.
{ lib, gitSettings }:
let
  # section.lowercasevar -> "canonicalVar"
  canonical = import ./_canonical-variables-generated.nix;

  # Lowercase only the section part, preserve subsection (e.g., includeIf "gitdir:~/")
  # Section is before first space/quote, subsection is the quoted part
  lowerSectionOnly =
    name:
    let
      match = builtins.match "([^ \"]+)(.*)" name;
    in
    if match == null then
      name |> lib.toLower
    else
      (builtins.elemAt match 0 |> lib.toLower) + builtins.elemAt match 1;

  checkSection =
    sectionName: attrs:
    let
      fixedSection = lowerSectionOnly sectionName;
      baseSection = sectionName |> lib.splitString " " |> builtins.head |> lib.toLower;
      sectionVars = canonical.${baseSection} or { };

      badSection = sectionName != fixedSection;

      badVars =
        attrs
        |> lib.filterAttrs (_: v: !builtins.isAttrs v)
        |> lib.mapAttrsToList (
          varName: _:
          let
            lowerVar = varName |> lib.toLower;
            canonicalVar = sectionVars.${lowerVar} or null;
          in
          if canonicalVar != null && canonicalVar != varName then
            [
              {
                path = "${sectionName}.${varName}";
                fix = "${fixedSection}.${canonicalVar}";
              }
            ]
          else if badSection && canonicalVar == null then
            [
              {
                path = "${sectionName}.${varName}";
                fix = "${fixedSection}.${varName}";
              }
            ]
          else
            [ ]
        )
        |> lib.concatLists;
    in
    badVars;

  issues =
    gitSettings
    |> lib.mapAttrsToList (name: val: if builtins.isAttrs val then checkSection name val else [ ])
    |> lib.concatLists;
in
{
  inherit issues;

  hasErrors = issues != [ ];

  errorMessage =
    if issues == [ ] then
      ""
    else
      ''
        programs.git.settings uses non-canonical casing.
        Sections should be lowercase, variables should use camelCase:

        ${issues |> lib.concatMapStringsSep "\n" (i: "  ${i.path} -> ${i.fix}")}
      '';
}
