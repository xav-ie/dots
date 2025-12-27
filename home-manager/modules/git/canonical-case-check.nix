# Checks that git config uses canonical casing:
# - Sections should be lowercase (subsections are case-sensitive, left unchanged)
# - Variables should use camelCase per git documentation
{
  config,
  lib,
  ...
}:
let
  cfg = config.programs.git;

  # section.lowercasevar -> "canonicalVar"
  canonical = import ./canonical-variables-generated.nix;

  # Lowercase only the section part, preserve subsection (e.g., includeIf "gitdir:~/")
  # Section is before first space/quote, subsection is the quoted part
  lowerSectionOnly =
    name:
    let
      match = builtins.match "([^ \"]+)(.*)" name;
    in
    if match == null then lib.toLower name else lib.toLower (lib.elemAt match 0) + lib.elemAt match 1;

  checkSection =
    sectionName: attrs:
    let
      fixedSection = lowerSectionOnly sectionName;
      baseSection = lib.toLower (builtins.head (lib.splitString " " sectionName));
      sectionVars = canonical.${baseSection} or { };

      badSection = sectionName != fixedSection;

      badVars = lib.concatLists (
        lib.mapAttrsToList (
          varName: _:
          let
            lowerVar = lib.toLower varName;
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
        ) (lib.filterAttrs (_: v: !lib.isAttrs v) attrs)
      );
    in
    badVars;

  issues = lib.concatLists (
    lib.mapAttrsToList (name: val: if lib.isAttrs val then checkSection name val else [ ]) (
      cfg.settings or { }
    )
  );
in
{
  config = lib.mkIf (cfg.enable && issues != [ ]) {
    assertions = [
      {
        assertion = false;
        message = ''
          programs.git.settings uses non-canonical casing.
          Sections should be lowercase, variables should use camelCase:

          ${lib.concatMapStringsSep "\n" (i: "  ${i.path} -> ${i.fix}") issues}
        '';
      }
    ];
  };
}
